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

      # Create published event (with deduplication)
      begin
        # Check if published event already exists within the last 5 seconds
        recent_published = Event.where(
          board: board,
          action: "beads_issue_published"
        ).where("created_at > ?", 5.seconds.ago)
         .where("particulars->>'beads_issue_id' = ?", issue.id)
         .exists?

        unless recent_published
          creator = find_or_create_creator(issue.creator)

          Event.create!(
            board: board,
            creator: creator,
            eventable_type: "BeadsIssue",
            eventable_id: beads_issue_to_uuid(issue.id),
            action: "beads_issue_published",
            beads_issue_id: issue.id
          )

          Rails.logger.info("BeadsBridge: Created beads_issue_published event for #{issue.id}")
        else
          Rails.logger.debug("BeadsBridge: Skipping duplicate published event for #{issue.id}")
        end
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error("BeadsBridge: Failed to create published event for #{issue.id}: #{e.message}")
      end

      # Broadcast to UI
      broadcast_card_created(issue.id)
    end

    def handle_update(issue)
      # Change detection flow:
      # 1. Load previous state from cache (BeadsIssueState) with lock
      # 2. Compare to current issue data (ChangeDetector)
      # 3. Get semantic changes (StatusChange, CommentAddition, etc.)
      # 4. Update cache FIRST (prevents duplicate processing)
      # 5. Create events for each change
      #
      # Note: We use pessimistic locking to prevent race conditions where
      # multiple mutations for the same issue are processed simultaneously,
      # which would cause duplicate events.

      # Use transaction with lock to prevent race conditions
      BeadsIssueState.transaction do
        # Load previous state from cache with lock
        state = BeadsIssueState.lock.find_by(board_id: board.id, issue_id: issue.id)

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

        # Update cached state FIRST (before creating events)
        # This prevents duplicate event creation if the same mutation is processed multiple times
        begin
          state.update_snapshot!(current_snapshot)
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error("BeadsBridge: Failed to update cache for #{issue.id}: #{e.message}")
          # Continue - cache will be stale but not fatal
        end

        # Create events for each detected change
        changes.each do |change|
          create_event_for_change(issue, change)
        end

        # Broadcast UI updates (handles column moves)
        broadcast_card_moved(issue.id) if changes.any?
      end
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
    def create_event_for_change(issue, change)
      # Deduplication: Check if an identical event exists within the last 5 seconds
      # This prevents duplicate events from rapid-fire mutation processing
      # while allowing legitimate repeated actions (e.g., assign/unassign/reassign)
      recent_event = Event.where(
        board: board,
        action: change.event_action
      ).where("created_at > ?", 5.seconds.ago)
       .where("particulars->>'beads_issue_id' = ?", issue.id)
       .exists?

      if recent_event
        Rails.logger.debug("BeadsBridge: Skipping duplicate event #{change.event_action} for #{issue.id}")
        return
      end

      creator = find_or_create_creator(change.actor_email)

      event_attributes = {
        board: board,
        creator: creator,
        eventable_type: "BeadsIssue",
        eventable_id: beads_issue_to_uuid(issue.id),
        action: change.event_action,
        beads_issue_id: issue.id
      }

      # Add change-specific particulars
      particulars = change.event_particulars
      event_attributes.merge!(particulars) if particulars.present?

      Event.create!(event_attributes)

      Rails.logger.info("BeadsBridge: Created event #{change.event_action} for #{issue.id}")
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("BeadsBridge: Failed to create event: #{e.message}")
    end

    def find_or_create_creator(actor)
      # Handle User objects
      return actor if actor.is_a?(User)

      # Handle email strings
      email = actor.is_a?(String) ? actor : nil
      return beads_user if email.blank?

      # Try to find a User with this email in the account
      identity = Identity.find_by(email_address: email)
      if identity
        user = identity.users.find_by(account: board.account)
        return user if user
      end

      # Fall back to beads system user
      beads_user
    end

    def beads_user
      @beads_user ||= begin
        # Find beads user by email
        beads_identity = Identity.find_by(email_address: "hi@fizzybeads.com")
        if beads_identity
          user = board.account.users.find_by(identity: beads_identity)
          return user if user
        end

        # Last resort: use the board creator
        Rails.logger.warn("BeadsBridge: No beads user found, using board creator as fallback")
        board.creator
      end
    end

    def beads_issue_to_uuid(issue_id)
      # Generate deterministic UUID from issue ID for eventable_id
      # Use MD5 hash converted to UUID format
      digest = Digest::MD5.hexdigest("beads:#{issue_id}")
      "#{digest[0..7]}-#{digest[8..11]}-#{digest[12..15]}-#{digest[16..19]}-#{digest[20..31]}"
    end
end
