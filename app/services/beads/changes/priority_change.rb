# frozen_string_literal: true

module Beads
  module Changes
    class PriorityChange
      attr_reader :from, :to

      def initialize(from:, to:)
        @from, @to = from, to
      end

      def event_action
        "beads_issue_priority_changed"
      end

      def event_particulars
        { old_priority: from, new_priority: to }
      end

      def actor_email
        nil
      end

      def notifiable?
        false
      end
    end
  end
end
