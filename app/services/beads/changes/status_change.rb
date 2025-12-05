# frozen_string_literal: true

module Beads
  module Changes
    class StatusChange
      attr_reader :from, :to, :actor

      def initialize(from:, to:, actor: nil)
        @from, @to, @actor = from, to, actor
      end

      def event_action
        case to
        when "closed" then "beads_issue_closed"
        when "open"
          from == "closed" ? "beads_issue_reopened" : "beads_issue_started"
        when "in_progress" then "beads_issue_started"
        when "blocked" then "beads_issue_blocked"
        else "beads_issue_status_changed"
        end
      end

      def event_particulars
        { old_status: from, new_status: to }
      end

      def actor_email
        actor
      end

      def notifiable?
        true
      end
    end
  end
end
