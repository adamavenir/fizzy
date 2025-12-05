# frozen_string_literal: true

module Beads
  module Changes
    class DescriptionChange
      attr_reader :from, :to

      def initialize(from:, to:)
        @from, @to = from, to
      end

      def event_action
        "beads_issue_description_changed"
      end

      def event_particulars
        {
          old_description: from&.slice(0, 200),
          new_description: to&.slice(0, 200)
        }
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
