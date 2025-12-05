class User::DayTimeline
  include Serializable

  attr_reader :user, :day, :filter

  delegate :today?, to: :day

  def initialize(user, day, filter)
    @user, @day, @filter = user, day, filter
  end

  def has_activity?
    events.any?
  end

  def events
    filtered_events.where(created_at: window).order(created_at: :desc)
  end

  def next_day
    latest_event_before&.created_at
  end

  def earliest_time
    next_day&.tomorrow&.beginning_of_day
  end

  def latest_time
    day.yesterday.beginning_of_day
  end

  def added_column
    @added_column ||= build_column("Added", 1, events.where(action: %w[card_published card_reopened beads_issue_published beads_issue_reopened]))
  end

  def updated_column
    @updated_column ||= build_column("Updated", 2, events.where.not(action: %w[card_published card_closed card_reopened beads_issue_published beads_issue_closed beads_issue_reopened beads_issue_updated]))
  end

  def closed_column
    @closed_column ||= begin
      closed_events = events.where(action: %w[card_closed beads_issue_closed])
      # Filter out child beads issues when their parent was also closed in the same window
      filtered_events = filter_child_closures(closed_events)
      build_column("Done", 3, filtered_events)
    end
  end

  def cache_key
    ActiveSupport::Cache.expand_cache_key [ user, filter, day.to_date, events ], "day-timeline"
  end

  private
    TIMELINEABLE_ACTIONS = %w[
      card_assigned
      card_unassigned
      card_published
      card_closed
      card_reopened
      card_collection_changed
      card_board_changed
      card_postponed
      card_auto_postponed
      card_triaged
      card_sent_back_to_triage
      comment_created
      beads_issue_published
      beads_issue_closed
      beads_issue_reopened
      beads_issue_started
      beads_issue_blocked
      beads_issue_assigned
      beads_issue_unassigned
      beads_comment_created
    ]

    def filtered_events
      @filtered_events ||= begin
        events = timelineable_events
        events = events.where(creator_id: filter.creators.ids) if filter.creators.present?
        events
      end
    end

    # Filter out child issue closures when their parent was also closed in the same window
    def filter_child_closures(closed_events)
      # Only applies to beads issues
      beads_closed = closed_events.where(action: "beads_issue_closed").to_a
      return closed_events if beads_closed.empty?

      # Get all closed issue IDs in this window
      closed_issue_ids = beads_closed.map(&:beads_issue_id).compact
      return closed_events if closed_issue_ids.empty?

      # For each beads issue, check if it's a child and if parent was also closed
      child_event_ids = []

      beads_closed.each do |event|
        next unless event.beads_issue_id

        begin
          # Fetch the issue to check parent-child relationship
          issue = event.card
          next unless issue && issue.respond_to?(:is_child?)

          # If this is a child and its parent was also closed in this window, filter it out
          if issue.is_child? && issue.parent_issue_id && closed_issue_ids.include?(issue.parent_issue_id)
            child_event_ids << event.id
          end
        rescue => e
          Rails.logger.warn("DayTimeline: Failed to check parent-child for #{event.beads_issue_id}: #{e.message}")
        end
      end

      # Filter out the child events
      if child_event_ids.any?
        closed_events.where.not(id: child_event_ids)
      else
        closed_events
      end
    end

    def timelineable_events
      Event
        .preloaded
        .where(board: boards)
        .where(action: TIMELINEABLE_ACTIONS)
    end

    def boards
      filter.boards.presence || user.boards
    end

    def latest_event_before
      filtered_events.where(created_at: ...day.beginning_of_day).chronologically.last
    end

    def build_column(base_title, index, events)
      Column.new(self, base_title, index, events)
    end

    def window
      day.all_day
    end
end
