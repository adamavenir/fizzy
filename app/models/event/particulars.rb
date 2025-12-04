module Event::Particulars
  extend ActiveSupport::Concern

  included do
    store_accessor :particulars, :assignee_ids, :beads_issue_id
  end

  def assignees
    @assignees ||= User.where id: assignee_ids
  end
end
