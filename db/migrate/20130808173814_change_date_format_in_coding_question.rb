class ChangeDateFormatInCodingQuestion < ActiveRecord::Migration
  def up
    change_column :coding_questions, :last_commented_at, :datetime
  end

  def down
    change_column :coding_questions, :last_commented_at, :time
  end
end
