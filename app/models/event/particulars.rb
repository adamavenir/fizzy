module Event::Particulars
  extend ActiveSupport::Concern

  included do
    store_accessor :particulars,
      :assignee_ids,
      :beads_issue_id,
      :old_status,
      :new_status,
      :old_assignee,
      :new_assignee,
      :old_title,
      :new_title,
      :old_description,
      :new_description,
      :old_priority,
      :new_priority,
      :labels_added,
      :labels_removed,
      :comment_author,
      :comment_created_at,
      :comment_excerpt,
      :comment_body_hash
  end

  def assignees
    @assignees ||= User.where id: assignee_ids
  end
end
