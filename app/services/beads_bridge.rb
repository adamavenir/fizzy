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
      issue_id = mutation["IssueID"]

      begin
        case mutation["Type"]
        when "create"
          issue = fetch_issue(issue_id)
          return unless issue
          handle_create(issue)
        when "update"
          issue = fetch_issue(issue_id)
          return unless issue
          handle_update(issue)
        when "close", "delete"
          handle_delete(issue_id)
        end
      rescue BeadsClient::Error => e
        Rails.logger.warn("BeadsBridge: Cannot fetch issue #{issue_id}: #{e.message}")
        # For delete mutations, issue being gone is expected
        handle_delete(issue_id) if mutation["Type"] == "delete" || mutation["Type"] == "close"
        # For create/update mutations, skip this mutation
      rescue StandardError => e
        Rails.logger.error("BeadsBridge: Failed processing mutation for #{issue_id}: #{e.class.name} - #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n")) if Rails.env.development?
        # Don't raise - continue processing other mutations
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
    rescue StandardError => e
      Rails.logger.error("BeadsBridge: Failed to broadcast card created for #{issue_id}: #{e.message}")
      # Continue - broadcast failure is not critical
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
    rescue StandardError => e
      Rails.logger.error("BeadsBridge: Failed to broadcast card updated for #{issue_id}: #{e.message}")
      # Continue - broadcast failure is not critical
    end

    def broadcast_card_removed(issue_id)
      Turbo::StreamsChannel.broadcast_remove_to(
        board,
        target: "#{issue_id}_article"
      )
    rescue StandardError => e
      Rails.logger.error("BeadsBridge: Failed to broadcast card removed for #{issue_id}: #{e.message}")
      # Continue - broadcast failure is not critical
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

    # Mutation handlers
    def handle_create(issue)
      issue_data = serialize_issue(issue)

      # Store initial state in cache (use find_or_create for idempotency)
      begin
        state = BeadsIssueState.find_or_initialize_by(
          board_id: board.id,
          issue_id: issue.id
        )

        state.snapshot = issue_data.to_json
        state.synced_at = Time.current
        state.save!

        # Log the creation
        Rails.logger.info("BeadsBridge: Created state cache for #{issue.id}")
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("BeadsBridge: Failed to create cache for #{issue.id}: #{e.message}")
        # Continue - cache will be missing but not fatal for this mutation
      end

      # Create published event
      create_event_for_creation(issue.id)

      # Broadcast to UI
      broadcast_card_created(issue.id)
    end

    def handle_update(issue)
      # Change detection flow:
      # 1. Load previous state from cache (BeadsIssueState)
      # 2. Compare to current issue data (ChangeDetector)
      # 3. Get semantic changes (StatusChange, CommentAddition, etc.)
      # 4. Log changes (or create events in future)
      # 5. Update cache with new state for next comparison

      # Load previous state from cache
      state = BeadsIssueState.find_by(board_id: board.id, issue_id: issue.id)

      # No previous state: treat as first-time create (backfill)
      if state.nil?
        Rails.logger.info("BeadsBridge: No cached state for #{issue.id}, treating as create")
        return handle_create(issue)
      end

      # Compare states
      begin
        previous_snapshot = state.parsed_snapshot

        # If snapshot is empty (due to parsing error), rebuild
        if previous_snapshot.empty?
          Rails.logger.error("BeadsBridge: Empty/corrupted cache for #{issue.id}, rebuilding")
          state.destroy
          return handle_create(issue)
        end
      rescue JSON::ParserError => e
        Rails.logger.error("BeadsBridge: Corrupted cache for #{issue.id}, rebuilding: #{e.message}")
        # Delete corrupted cache and rebuild
        state.destroy
        return handle_create(issue)
      end

      current_snapshot = serialize_issue(issue)

      detector = Beads::ChangeDetector.new(
        old_state: previous_snapshot,
        new_state: current_snapshot,
        issue: issue
      )

      changes = detector.detect_changes

      # Log detected changes
      changes.each do |change|
        Rails.logger.info("BeadsBridge: Detected change for #{issue.id}: #{change.class.name} - #{change.event_action}")
      end

      # Update cached state
      begin
        state.update_snapshot!(current_snapshot)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("BeadsBridge: Failed to update cache for #{issue.id}: #{e.message}")
        # Continue - cache will be stale but not fatal
      end

      # Broadcast UI updates (handles column moves)
      broadcast_card_moved(issue.id) if changes.any?
    end

    def handle_delete(issue_id)
      # Remove from state cache
      deleted_count = BeadsIssueState.where(board_id: board.id, issue_id: issue_id).destroy_all.size
      Rails.logger.info("BeadsBridge: Deleted #{deleted_count} state cache entries for #{issue_id}")

      # Broadcast removal
      broadcast_card_removed(issue_id)

      # Note: Don't delete events (preserve history)
    end

    def serialize_issue(beads_issue)
      # BeadsIssue doesn't have .attributes like ActiveRecord
      # Extract relevant fields manually
      {
        id: beads_issue.id,
        title: beads_issue.title,
        description: beads_issue.description,
        status: beads_issue.status,
        priority: beads_issue.priority,
        issue_type: beads_issue.issue_type,
        assignee: beads_issue.assignee,
        labels: beads_issue.labels,
        comments: beads_issue.comments.map do |comment|
          {
            author: comment.author,
            body: comment.body,
            created_at: comment.created_at&.iso8601
          }
        end,
        created_at: beads_issue.created_at&.iso8601,
        updated_at: beads_issue.updated_at&.iso8601,
        closed_at: beads_issue.closed_at&.iso8601
      }
    end

    # Event creation methods
    def create_event_for_creation(issue_id)
      issue = fetch_issue(issue_id)
      return unless issue

      Event.create!(
        board: board,
        creator: issue.creator,
        eventable_type: "BeadsIssue",
        eventable_id: uuid_for_issue(issue_id),
        action: "beads_issue_published",
        beads_issue_id: issue_id
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("BeadsBridge: Failed to create event for #{issue_id}: #{e.message}")
    end

    def create_event_for_update(issue_id, mutation)
      issue = fetch_issue(issue_id)
      return unless issue

      # Check if this is a status change by comparing current status
      # We need to fetch the previous issue state to detect status changes
      # For now, create a generic update event
      Event.create!(
        board: board,
        creator: issue.creator,
        eventable_type: "BeadsIssue",
        eventable_id: uuid_for_issue(issue_id),
        action: "beads_issue_updated",
        beads_issue_id: issue_id
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("BeadsBridge: Failed to create update event for #{issue_id}: #{e.message}")
    end

    def create_event_for_closure(issue_id)
      issue = fetch_issue(issue_id)
      return unless issue

      Event.create!(
        board: board,
        creator: issue.creator,
        eventable_type: "BeadsIssue",
        eventable_id: uuid_for_issue(issue_id),
        action: "beads_issue_closed",
        beads_issue_id: issue_id
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("BeadsBridge: Failed to create closure event for #{issue_id}: #{e.message}")
    end

    def uuid_for_issue(issue_id)
      # Generate a deterministic UUID from the issue ID using MD5
      Digest::MD5.hexdigest(issue_id)
    end
end
