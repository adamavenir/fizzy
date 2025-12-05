# frozen_string_literal: true

module Beads
  class ChangeDetector
    attr_reader :old_state, :new_state, :issue

    def initialize(old_state:, new_state:, issue:)
      @old_state = old_state&.deep_symbolize_keys || {}
      @new_state = new_state.deep_symbolize_keys
      @issue = issue
    end

    def detect_changes
      changes = []

      if status_changed?
        changes << Changes::StatusChange.new(
          from: old_state[:status],
          to: new_state[:status],
          actor: new_state[:assignee]
        )
      end

      if assignee_changed?
        changes << Changes::AssignmentChange.new(
          from: old_state[:assignee],
          to: new_state[:assignee]
        )
      end

      if title_changed?
        changes << Changes::TitleChange.new(
          from: old_state[:title],
          to: new_state[:title]
        )
      end

      if description_changed?
        changes << Changes::DescriptionChange.new(
          from: old_state[:description],
          to: new_state[:description]
        )
      end

      if priority_changed?
        changes << Changes::PriorityChange.new(
          from: old_state[:priority],
          to: new_state[:priority]
        )
      end

      if labels_changed?
        added, removed = label_diff
        changes << Changes::LabelsChange.new(
          added: added,
          removed: removed
        )
      end

      new_comments = detect_new_comments
      new_comments.each do |comment_hash|
        changes << Changes::CommentAddition.new(comment_hash)
      end

      changes
    end

    def new_issue?
      old_state.empty?
    end

    private

    def status_changed?
      old_state[:status] != new_state[:status]
    end

    def assignee_changed?
      old_state[:assignee] != new_state[:assignee]
    end

    def title_changed?
      normalize_string(old_state[:title]) != normalize_string(new_state[:title])
    end

    def description_changed?
      normalize_string(old_state[:description]) != normalize_string(new_state[:description])
    end

    def priority_changed?
      old_state[:priority] != new_state[:priority]
    end

    def labels_changed?
      old_labels = Array(old_state[:labels]).sort
      new_labels = Array(new_state[:labels]).sort
      old_labels != new_labels
    end

    def label_diff
      old_labels = Array(old_state[:labels])
      new_labels = Array(new_state[:labels])
      added = new_labels - old_labels
      removed = old_labels - new_labels
      [added, removed]
    end

    def detect_new_comments
      old_comments = Array(old_state[:comments])
      new_comments = Array(new_state[:comments])

      new_comments.reject do |new_comment|
        old_comments.any? do |old_comment|
          comments_match?(old_comment, new_comment)
        end
      end
    end

    def comments_match?(c1, c2)
      c1 = c1.deep_symbolize_keys
      c2 = c2.deep_symbolize_keys

      c1[:created_at] == c2[:created_at] &&
        c1[:author] == c2[:author] &&
        c1[:body] == c2[:body]
    end

    def normalize_string(value)
      value.to_s.strip
    end
  end
end
