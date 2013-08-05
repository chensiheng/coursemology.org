class TrainingsController < ApplicationController
  load_and_authorize_resource :course
  load_and_authorize_resource :training, through: :course

  before_filter :load_general_course_data, only: [:show, :index, :edit, :new]

  def index
    @is_new = {}
    @tags_map = {}
    @selected_tags = params[:tags]
    @display_columns = {}
    @course.training_columns_display.each do |cp|
      @display_columns[cp.preferable_item.name] = cp.prefer_value
    end
    @time_format =  @course.training_time_format

    if @selected_tags
      tags = Tag.find(@selected_tags)
      training_ids = tags.map { |tag| tag.trainings.map{ |t| t.id } }.reduce(:&)
      @trainings = @course.trainings.accessible_by(current_ability)
      .order(:open_at).reverse_order.find(training_ids)

      tags.each { |tag| @tags_map[tag.id] = true }
    else
      @trainings = @course.trainings.accessible_by(current_ability)
      .order(:open_at).reverse_order
      .page(params[:page])
      @can_paginate = true
    end

    if curr_user_course.id
      unseen = @trainings - curr_user_course.seen_trainings
      unseen.each do |tn|
        @is_new[tn.id] = true
        curr_user_course.mark_as_seen(tn)
      end
    end

    @trainings_with_sbm = []
    @trainings.each do |training|
      if curr_user_course.id
        std_sbm = TrainingSubmission.where(
            std_course_id: curr_user_course.id,
            training_id: training.id
        ).last
      end
      @trainings_with_sbm << {
          training: training,
          submission: std_sbm
      }
    end
  end

  def show
    @steps = @training.questions
    if curr_user_course.is_student?
      @submission = @training.get_final_sbm_by_std(curr_user_course)
    end
  end

  def new
    @training.exp = 1000
    @training.open_at = DateTime.now.beginning_of_day
    @tags = @course.tags
    @asm_tags = {}
  end

  def create
    @training.pos = @course.trainings.count - 1
    @training.creator = current_user
    @training.update_tags(params[:tags])
    if params[:files]
      @training.attach_files(params[:files].values)
    end

    respond_to do |format|
      if @training.save
        @training.schedule_mail(@course.user_courses, course_training_url(@course, @training))
        format.html { redirect_to course_training_path(@course, @training),
                                  notice: "The training '#{@training.title}' has been created." }
      else
        format.html { render action: "new" }
      end
    end
  end

  def edit
    @tags = @course.tags
    @asm_tags = {}
    @training.asm_tags.each { |asm_tag| @asm_tags[asm_tag.tag_id] = true }
  end

  def update
    @training.update_tags(params[:tags])
    if params[:files]
      @training.attach_files(params[:files].values)
    end
    reschedule_email = Time.parse(params[:training][:open_at]) != @training.open_at
    respond_to do |format|
      if reschedule_email
        @training.schedule_mail(@course.user_courses, course_training_url(@course, @training))
      end
      if @training.update_attributes(params[:training])
        format.html { redirect_to course_training_url(@course, @training),
                                  notice: "The training '#{@training.title}' has been updated." }
      else
        format.html { render action: "edit" }
      end
    end

  end

  def destroy
    @training.destroy

    respond_to do |format|
      format.html { redirect_to course_trainings_url,
                                notice: "The training '#{@training.title}' has been removed." }
    end
  end
end
