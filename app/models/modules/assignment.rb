module Assignment

  def self.included(base)
    base.class_eval do
      scope :closed, lambda { where("close_at < ?", Time.now) }
      scope :still_open, lambda { where("close_at >= ? ", Time.now) }
      scope :opened, lambda { where("open_at <= ? ", Time.now) }
      scope :future, lambda { where("open_at > ? ", Time.now) }

      has_many :as_asm_reqs, class_name: "AsmReq", as: :asm, dependent: :destroy
      has_many :as_requirements, through: :as_asm_reqs, source: :as_requirements

      has_many :asm_qns, as: :asm, dependent: :destroy

      has_many :asm_tags, as: :asm, dependent: :destroy
      has_many :tags, through: :asm_tags
      has_many :queued_jobs, as: :owner, class_name: "QueuedJob", dependent: :destroy

      after_save :after_save_asm

      paginates_per 10
    end
  end

  def get_title
    "#{self.class.name} : #{self.title}"
  end

  def get_path
    raise NotImplementedError
  end

  def get_final_sbm_by_std(std_course_id)
    self.sbms.find_by_std_course_id(std_course_id)
  end

  def get_qn_pos(qn)
    self.asm_qns.each_with_index do |asm_qn, i|
      if asm_qn.qn == qn
        return (asm_qn.pos || i) + 1
      end
    end
    -1
  end

  def update_qns_pos
    self.asm_qns.each_with_index do |asm_qn, i|
      asm_qn.pos = i
      asm_qn.save
    end
  end

  def add_tags(tags)
    tags ||= []
    tags.each do |tag_id|
      self.asm_tags.build(
          tag_id: tag_id,
          max_exp: exp
      )
    end
    self.save
  end

  def update_tags(all_tags)
    all_tags ||= []
    all_tags = all_tags.collect { |id| id.to_i }
    removed_asm_tags = []
    existing_tags = []
    self.asm_tags.each do |asm_tag|
      if !all_tags.include?(asm_tag.tag_id)
        removed_asm_tags << asm_tag.id
      else
        existing_tags << asm_tag.tag_id
      end
    end
    AsmTag.delete(removed_asm_tags)
    self.add_tags(all_tags - existing_tags)
  end

  def after_save_asm
    self.tags.each { |tag| tag.update_max_exp }
  end

  def schedule_mail(ucs, redirect_to)
    type = self.class
    QueuedJob.destroy(self.queued_jobs)
    course = self.course
    if type == Mission && !course.email_notify_enabled?(PreferableItem.new_mission)
      return
    end
    if type == Training && !course.email_notify_enabled?(PreferableItem.new_training)
      return
    end
    ucs.each do |uc|
      user = uc.user
      if type == Mission
        delayed_job = UserMailer.delay(:run_at => self.open_at).new_mission(user.name, user.email, self.title, course.title, redirect_to)
      elsif type == Training
        delayed_job = UserMailer.delay(:run_at => self.open_at).new_training(user.name, user.email, self.title, course.title, redirect_to)
      end
      self.queued_jobs.create(delayed_job_id: delayed_job.id)
    end
  end

end
