# Query service for fetching BeadsIssue cards from a board's beads repo.
# Handles the hybrid column model where columns map to either fizzy: labels or beads statuses.
#
# Usage:
#   query = BeadsCardQuery.new(board)
#   cards = query.for_column(column)  # => Array<BeadsIssue>
#
class BeadsCardQuery
  def initialize(board)
    @board = board
    @client = board.beads_client
  end

  # Returns BeadsIssue objects for a given column
  def for_column(column)
    return [] unless @client

    issues = fetch_issues_for_column(column)
    sort_issues(wrap_issues(issues))
  end

  # Returns all BeadsIssue objects for the board
  def all
    return [] unless @client
    issues = @client.list
    sort_issues(wrap_issues(issues))
  end

  private
    # Wrap issue data in BeadsIssue objects with board reference
    def wrap_issues(issues)
      issues.map do |data|
        issue = BeadsIssue.new(data)
        issue.board = @board
        issue
      end
    end
    def fetch_issues_for_column(column)
      case column.column_type
      when "fizzy_tag"
        # Fizzy triage columns: status:open with specific fizzy: label
        @client.list(status: "open", labels: [column.beads_value])
      when "beads_status"
        if column.beads_value == "open"
          # Open column: status:open WITHOUT any fizzy: labels
          all_open = @client.list(status: "open")
          all_open.reject { |i| has_fizzy_label?(i) }
        else
          # Other status columns: direct status match
          @client.list(status: column.beads_value)
        end
      else
        []
      end
    end

    def has_fizzy_label?(issue_data)
      labels = issue_data["labels"] || []
      labels.any? { |l| l.to_s.start_with?("fizzy:") }
    end

    # Sort by priority (0=highest), then by created_at (oldest first)
    def sort_issues(issues)
      issues.sort_by { |i| [i.priority || 2, i.created_at || Time.at(0)] }
    end
end
