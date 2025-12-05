# frozen_string_literal: true

class BeadsIssueState < ApplicationRecord
  belongs_to :board

  validates :issue_id, presence: true, uniqueness: { scope: :board_id }
  validates :snapshot, presence: true
  validates :synced_at, presence: true

  scope :for_issue, ->(board, issue_id) { where(board: board, issue_id: issue_id) }

  # Parse snapshot JSON when reading
  def parsed_snapshot
    @parsed_snapshot ||= JSON.parse(snapshot).deep_symbolize_keys
  rescue JSON::ParserError => e
    Rails.logger.error("BeadsIssueState: Invalid JSON in snapshot for issue #{issue_id}: #{e.message}")
    {}
  end

  # Update with new snapshot data
  def update_snapshot!(issue_data_hash)
    update!(
      snapshot: issue_data_hash.to_json,
      synced_at: Time.current
    )
  end
end
