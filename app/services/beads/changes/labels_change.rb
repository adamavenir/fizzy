# frozen_string_literal: true

module Beads
  module Changes
    class LabelsChange
      attr_reader :added, :removed

      def initialize(added:, removed:)
        @added, @removed = added, removed
      end

      def event_action
        "beads_issue_labels_changed"
      end

      def event_particulars
        { labels_added: added, labels_removed: removed }
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
