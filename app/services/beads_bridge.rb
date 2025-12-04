class BeadsBridge
  class Error < StandardError; end

  attr_reader :board

  def initialize(board)
    @board = board
  end

  def poll_and_broadcast
    return unless board.beads_enabled?

    mutations = fetch_mutations

    # Only broadcast if there are actual mutations
    if mutations.any?
      Rails.logger.info("BeadsBridge: Processing #{mutations.size} mutations for board #{board.id}")
      process_mutations(mutations)
      update_timestamp(mutations.last["Timestamp"])
    end
  rescue BeadsClient::DaemonNotRunningError => e
    Rails.logger.warn("BeadsBridge: Daemon not running for board #{board.id}, skipping poll")
    # Don't raise - just skip this poll cycle
  rescue BeadsClient::Error => e
    Rails.logger.error("BeadsBridge poll error for board #{board.id}: #{e.message}")
    raise Error, e.message
  end

  private
    def fetch_mutations
      client = board.beads_client
      client.get_mutations(since: board.last_mutation_timestamp)
    end

    def process_mutations(mutations)
      return if mutations.empty?

      mutations.each do |mutation|
        process_mutation(mutation)
      end
    end

    def process_mutation(mutation)
      case mutation["Type"]
      when "create"
        broadcast_card_created(mutation["IssueID"])
      when "update"
        # For updates, remove and re-add to handle potential status changes
        broadcast_card_moved(mutation["IssueID"])
      when "close", "delete"
        broadcast_card_removed(mutation["IssueID"])
      end
    end

    def broadcast_card_created(issue_id)
      issue = fetch_issue(issue_id)
      return unless issue

      column = find_column_for_issue(issue)
      return unless column

      # Refresh the column frame since it may be lazily loaded
      Turbo::StreamsChannel.broadcast_refresh_to(
        board,
        target: ActionView::RecordIdentifier.dom_id(column, :cards)
      )
    end

    def broadcast_card_updated(issue_id)
      issue = fetch_issue(issue_id)
      return unless issue

      # Replace the card preview in the list
      Turbo::StreamsChannel.broadcast_replace_to(
        board,
        target: ActionView::RecordIdentifier.dom_id(issue, :article),
        partial: "cards/display/beads_preview",
        locals: { card: issue, draggable: true }
      )
    end

    def broadcast_card_removed(issue_id)
      Turbo::StreamsChannel.broadcast_remove_to(
        board,
        target: "#{issue_id}_article"
      )
    end

    def broadcast_card_moved(issue_id)
      # For status changes, remove from all columns and re-add to the correct one
      broadcast_card_removed(issue_id)
      broadcast_card_created(issue_id)
    end

    def fetch_issue(issue_id)
      return nil unless issue_id.present?

      issue_data = board.beads_client.show(issue_id)
      issue = BeadsIssue.new(issue_data)
      issue.board = board
      issue
    rescue BeadsClient::Error => e
      Rails.logger.error("BeadsBridge: Failed to fetch issue #{issue_id}: #{e.message}")
      nil
    end

    def find_column_for_issue(issue)
      case issue.status
      when "open"
        board.columns.find_by(beads_value: "open")
      when "in_progress"
        board.columns.find_by(beads_value: "in_progress")
      when "blocked"
        board.columns.find_by(beads_value: "blocked")
      else
        nil
      end
    end

    def update_timestamp(timestamp)
      return unless timestamp

      # Convert ISO8601 timestamp to milliseconds since epoch
      timestamp_ms = (Time.parse(timestamp).to_f * 1000).to_i

      board.update_column(:last_mutation_timestamp, timestamp_ms)
      Rails.logger.info("BeadsBridge: Updated timestamp to #{timestamp_ms} (#{timestamp})")
    end
end
