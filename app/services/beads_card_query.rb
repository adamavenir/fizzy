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
    wrapped = wrap_issues(issues)

    # Enrich with parent-child data and filter if needed
    if needs_parent_child_filtering?(column)
      enrich_with_parent_child_data(wrapped)
      wrapped = filter_children(wrapped)
    elsif needs_parent_child_badges?(column)
      # Still enrich for badge display, but don't filter
      enrich_with_parent_child_data(wrapped)
    end

    sort_issues(wrapped)
  rescue BeadsClient::DaemonNotRunningError => e
    Rails.logger.warn("BeadsCardQuery: Daemon not running for board #{@board.id}")
    []
  end

  # Returns all BeadsIssue objects for the board
  def all
    return [] unless @client
    issues = @client.list
    sort_issues(wrap_issues(issues))
  rescue BeadsClient::DaemonNotRunningError => e
    Rails.logger.warn("BeadsCardQuery: Daemon not running for board #{@board.id}")
    []
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

    def needs_parent_child_filtering?(column)
      # Only filter if board setting is enabled
      board = column.respond_to?(:board) ? column.board : @board
      return false unless board&.hide_child_cards

      # Hide children in: Open, Not Now
      column.beads_value == "open" || column.beads_value == "fizzy:not-now"
    end

    def needs_parent_child_badges?(column)
      # Show badges in all other columns
      !needs_parent_child_filtering?(column)
    end

    def enrich_with_parent_child_data(issues)
      # Fetch dependency metadata for each issue
      issues.each do |issue|
        begin
          details = @client.show(issue.id)

          # Inject dependency/dependent data (convert to symbol keys for BeadsIssue compatibility)
          dependencies = (details["dependencies"] || []).map(&:deep_symbolize_keys)
          dependents = (details["dependents"] || []).map(&:deep_symbolize_keys)

          issue.instance_variable_set(:@dependencies_data, dependencies)
          issue.instance_variable_set(:@dependents_data, dependents)

          # Clear memoization to force recalculation
          issue.instance_variable_set(:@is_child, nil)
          issue.instance_variable_set(:@child_issues, nil)
          issue.instance_variable_set(:@open_child_count, nil)
        rescue => e
          Rails.logger.warn("Failed to fetch dependencies for #{issue.id}: #{e.message}")
          # Set empty arrays as fallback
          issue.instance_variable_set(:@dependencies_data, [])
          issue.instance_variable_set(:@dependents_data, [])
        end
      end
    end

    def filter_children(issues)
      # Remove issues that are children of other issues
      issues.reject(&:is_child?)
    end
end
