# Value object that wraps a BeadsIssue to look like a Search::Record
# This allows beads search results to work with the existing search UI
class BeadsSearchResult
  attr_reader :issue, :board

  def initialize(issue, board)
    @issue = issue
    @board = board
  end

  # Search::Record interface compatibility
  # Returns a URL string instead of the issue object for link_to compatibility
  def source
    "/beads/boards/#{board.id}/issues/#{issue.id}"
  end

  def card
    issue
  end

  def comment
    nil
  end

  def card_id
    issue.id
  end

  def card_title
    issue.title
  end

  def card_description
    issue.description&.truncate(200)
  end

  def comment_body
    nil
  end

  def created_at
    issue.created_at
  end

  # Delegation to issue for compatibility
  delegate :id, to: :issue
end
