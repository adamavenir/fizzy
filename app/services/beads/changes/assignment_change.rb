# frozen_string_literal: true

module Beads
  module Changes
    class AssignmentChange
      attr_reader :from, :to

      def initialize(from:, to:)
        @from, @to = from, to
      end

      def event_action
        to.present? ? "beads_issue_assigned" : "beads_issue_unassigned"
      end

      def event_particulars
        { old_assignee: from, new_assignee: to }
      end

      def actor_email
        to || from
      end

      def notifiable?
        to.present?
      end
    end
  end
end
