# frozen_string_literal: true

module Beads
  module Changes
    class CommentAddition
      attr_reader :comment

      def initialize(comment_hash)
        @comment = comment_hash.deep_symbolize_keys
      end

      def event_action
        "beads_comment_created"
      end

      def event_particulars
        {
          comment_author: comment[:author],
          comment_created_at: comment[:created_at],
          comment_excerpt: truncate_comment(comment[:body]),
          comment_body_hash: hash_comment(comment[:body])
        }
      end

      def actor_email
        comment[:author]
      end

      def notifiable?
        true
      end

      private

      def truncate_comment(body)
        body&.slice(0, 200) || ""
      end

      def hash_comment(body)
        Digest::SHA256.hexdigest(body || "")
      end
    end
  end
end
