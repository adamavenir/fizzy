module User::BeadsSearcher
  extend ActiveSupport::Concern

  # Search across all beads-enabled boards for this user
  def search_beads(query)
    beads_boards = boards.select(&:beads_enabled?)
    return [] if beads_boards.empty?

    # Search each beads board and collect results
    results = beads_boards.flat_map do |board|
      issues = board.beads_client.search(query: query, limit: 50)
      issues.map do |issue_data|
        issue = BeadsIssue.new(issue_data)
        issue.board = board
        BeadsSearchResult.new(issue, board)
      end
    rescue BeadsClient::Error => e
      Rails.logger.error("Beads search error for board #{board.id}: #{e.message}")
      []
    end

    # Sort by created_at desc (most recent first)
    results.sort_by { |r| r.created_at }.reverse
  end

  # Check if user has any beads boards
  def has_beads_boards?
    boards.any?(&:beads_enabled?)
  end
end
