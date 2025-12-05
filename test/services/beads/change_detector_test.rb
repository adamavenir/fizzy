# frozen_string_literal: true

require "test_helper"
require "ostruct"

class Beads::ChangeDetectorTest < ActiveSupport::TestCase
  # ====================
  # New Issue Detection
  # ====================

  test "new_issue? returns true when old_state is nil" do
    detector = Beads::ChangeDetector.new(
      old_state: nil,
      new_state: { id: "fizzy-1", title: "Test" },
      issue: mock_issue
    )
    assert detector.new_issue?
  end

  test "new_issue? returns true when old_state is empty hash" do
    detector = Beads::ChangeDetector.new(
      old_state: {},
      new_state: { id: "fizzy-1", title: "Test" },
      issue: mock_issue
    )
    assert detector.new_issue?
  end

  test "new_issue? returns false when old_state exists" do
    detector = Beads::ChangeDetector.new(
      old_state: { id: "fizzy-1", title: "Test" },
      new_state: { id: "fizzy-1", title: "Test" },
      issue: mock_issue
    )
    assert_not detector.new_issue?
  end

  # ====================
  # No Changes
  # ====================

  test "detect_changes returns empty array when nothing changed" do
    state = { title: "Test", status: "open", assignee: nil, priority: 2, labels: ["bug"], description: "Desc" }
    detector = Beads::ChangeDetector.new(
      old_state: state,
      new_state: state.dup,
      issue: mock_issue
    )
    assert_equal [], detector.detect_changes
  end

  test "detect_changes returns empty array when only order of labels differs" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug", "feature"] },
      new_state: { labels: ["feature", "bug"] },
      issue: mock_issue
    )
    assert_equal [], detector.detect_changes
  end

  # ====================
  # Status Changes
  # ====================

  test "detects status change from open to in_progress" do
    detector = Beads::ChangeDetector.new(
      old_state: { status: "open" },
      new_state: { status: "in_progress" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::StatusChange, changes.first
    assert_equal "open", changes.first.from
    assert_equal "in_progress", changes.first.to
  end

  test "detects status change from in_progress to closed" do
    detector = Beads::ChangeDetector.new(
      old_state: { status: "in_progress" },
      new_state: { status: "closed" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::StatusChange, changes.first
    assert_equal "in_progress", changes.first.from
    assert_equal "closed", changes.first.to
  end

  test "detects status change from closed to open (reopened)" do
    detector = Beads::ChangeDetector.new(
      old_state: { status: "closed" },
      new_state: { status: "open" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::StatusChange, changes.first
    assert_equal "closed", changes.first.from
    assert_equal "open", changes.first.to
  end

  test "detects status change from in_progress to blocked" do
    detector = Beads::ChangeDetector.new(
      old_state: { status: "in_progress" },
      new_state: { status: "blocked" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::StatusChange, changes.first
    assert_equal "blocked", changes.first.to
  end

  test "status change includes actor when provided" do
    detector = Beads::ChangeDetector.new(
      old_state: { status: "open" },
      new_state: { status: "closed", assignee: "alice@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    status_change = changes.find { |c| c.is_a?(Beads::Changes::StatusChange) }
    assert_equal "alice@example.com", status_change.actor
  end

  # ====================
  # Assignment Changes
  # ====================

  test "detects assignment from nil to email (assigned)" do
    detector = Beads::ChangeDetector.new(
      old_state: { assignee: nil },
      new_state: { assignee: "alice@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::AssignmentChange, changes.first
    assert_nil changes.first.from
    assert_equal "alice@example.com", changes.first.to
  end

  test "detects assignment from email to nil (unassigned)" do
    detector = Beads::ChangeDetector.new(
      old_state: { assignee: "alice@example.com" },
      new_state: { assignee: nil },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::AssignmentChange, changes.first
    assert_equal "alice@example.com", changes.first.from
    assert_nil changes.first.to
  end

  test "detects reassignment from one email to another" do
    detector = Beads::ChangeDetector.new(
      old_state: { assignee: "alice@example.com" },
      new_state: { assignee: "bob@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::AssignmentChange, changes.first
    assert_equal "alice@example.com", changes.first.from
    assert_equal "bob@example.com", changes.first.to
  end

  test "no assignment change when assignee stays the same" do
    detector = Beads::ChangeDetector.new(
      old_state: { assignee: "alice@example.com" },
      new_state: { assignee: "alice@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assignment_changes = changes.select { |c| c.is_a?(Beads::Changes::AssignmentChange) }
    assert_equal 0, assignment_changes.length
  end

  # ====================
  # Title Changes
  # ====================

  test "detects title change" do
    detector = Beads::ChangeDetector.new(
      old_state: { title: "Old Title" },
      new_state: { title: "New Title" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::TitleChange, changes.first
    assert_equal "Old Title", changes.first.from
    assert_equal "New Title", changes.first.to
  end

  test "normalizes whitespace in title comparison" do
    detector = Beads::ChangeDetector.new(
      old_state: { title: "  Test Title  " },
      new_state: { title: "Test Title" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    title_changes = changes.select { |c| c.is_a?(Beads::Changes::TitleChange) }
    assert_equal 0, title_changes.length
  end

  test "detects title change from nil to value" do
    detector = Beads::ChangeDetector.new(
      old_state: { title: nil },
      new_state: { title: "New Title" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::TitleChange, changes.first
  end

  # ====================
  # Description Changes
  # ====================

  test "detects description change" do
    detector = Beads::ChangeDetector.new(
      old_state: { description: "Old description" },
      new_state: { description: "New description" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::DescriptionChange, changes.first
    assert_equal "Old description", changes.first.from
    assert_equal "New description", changes.first.to
  end

  test "normalizes whitespace in description comparison" do
    detector = Beads::ChangeDetector.new(
      old_state: { description: "  Test  " },
      new_state: { description: "Test" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    description_changes = changes.select { |c| c.is_a?(Beads::Changes::DescriptionChange) }
    assert_equal 0, description_changes.length
  end

  test "detects description change from nil to value" do
    detector = Beads::ChangeDetector.new(
      old_state: { description: nil },
      new_state: { description: "New description" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::DescriptionChange, changes.first
  end

  test "detects description change from value to nil" do
    detector = Beads::ChangeDetector.new(
      old_state: { description: "Old description" },
      new_state: { description: nil },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::DescriptionChange, changes.first
  end

  # ====================
  # Priority Changes
  # ====================

  test "detects priority change from 1 to 0" do
    detector = Beads::ChangeDetector.new(
      old_state: { priority: 1 },
      new_state: { priority: 0 },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::PriorityChange, changes.first
    assert_equal 1, changes.first.from
    assert_equal 0, changes.first.to
  end

  test "detects priority change from nil to value" do
    detector = Beads::ChangeDetector.new(
      old_state: { priority: nil },
      new_state: { priority: 2 },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::PriorityChange, changes.first
    assert_nil changes.first.from
    assert_equal 2, changes.first.to
  end

  test "no priority change when priority stays the same" do
    detector = Beads::ChangeDetector.new(
      old_state: { priority: 2 },
      new_state: { priority: 2 },
      issue: mock_issue
    )

    changes = detector.detect_changes
    priority_changes = changes.select { |c| c.is_a?(Beads::Changes::PriorityChange) }
    assert_equal 0, priority_changes.length
  end

  # ====================
  # Label Changes
  # ====================

  test "detects labels added" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug"] },
      new_state: { labels: ["bug", "p0"] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    label_change = changes.first
    assert_instance_of Beads::Changes::LabelsChange, label_change
    assert_equal ["p0"], label_change.added
    assert_equal [], label_change.removed
  end

  test "detects labels removed" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug", "p0"] },
      new_state: { labels: ["bug"] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    label_change = changes.first
    assert_instance_of Beads::Changes::LabelsChange, label_change
    assert_equal [], label_change.added
    assert_equal ["p0"], label_change.removed
  end

  test "detects labels added and removed simultaneously" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug", "feature"] },
      new_state: { labels: ["bug", "p0"] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    label_change = changes.first
    assert_instance_of Beads::Changes::LabelsChange, label_change
    assert_equal ["p0"], label_change.added
    assert_equal ["feature"], label_change.removed
  end

  test "detects labels when old_state has nil labels" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: nil },
      new_state: { labels: ["bug"] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    label_change = changes.first
    assert_equal ["bug"], label_change.added
    assert_equal [], label_change.removed
  end

  test "detects labels when new_state has nil labels" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug"] },
      new_state: { labels: nil },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    label_change = changes.first
    assert_equal [], label_change.added
    assert_equal ["bug"], label_change.removed
  end

  test "handles label order differences as no change" do
    detector = Beads::ChangeDetector.new(
      old_state: { labels: ["bug", "feature"] },
      new_state: { labels: ["feature", "bug"] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    label_changes = changes.select { |c| c.is_a?(Beads::Changes::LabelsChange) }
    assert_equal 0, label_changes.length
  end

  # ====================
  # Comment Detection
  # ====================

  test "detects new comment added" do
    old_state = {
      comments: [
        { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" }
      ]
    }
    new_state = {
      comments: [
        { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" },
        { author: "bob@example.com", body: "Second", created_at: "2025-12-04T11:00:00Z" }
      ]
    }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 1, comment_changes.length
    assert_equal "bob@example.com", comment_changes.first.comment[:author]
    assert_equal "Second", comment_changes.first.comment[:body]
  end

  test "detects multiple new comments added" do
    old_state = {
      comments: [
        { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" }
      ]
    }
    new_state = {
      comments: [
        { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" },
        { author: "bob@example.com", body: "Second", created_at: "2025-12-04T11:00:00Z" },
        { author: "charlie@example.com", body: "Third", created_at: "2025-12-04T12:00:00Z" }
      ]
    }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 2, comment_changes.length
  end

  test "does not detect existing comments as new" do
    comment = { author: "alice@example.com", body: "Test", created_at: "2025-12-04T10:00:00Z" }

    detector = Beads::ChangeDetector.new(
      old_state: { comments: [comment] },
      new_state: { comments: [comment] },
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 0, comment_changes.length
  end

  test "detects comments when old_state has nil comments" do
    detector = Beads::ChangeDetector.new(
      old_state: { comments: nil },
      new_state: {
        comments: [
          { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" }
        ]
      },
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 1, comment_changes.length
  end

  test "detects comments when old_state has empty array" do
    detector = Beads::ChangeDetector.new(
      old_state: { comments: [] },
      new_state: {
        comments: [
          { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" }
        ]
      },
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 1, comment_changes.length
  end

  test "detects comments with string keys" do
    old_state = {
      comments: [
        { "author" => "alice@example.com", "body" => "First", "created_at" => "2025-12-04T10:00:00Z" }
      ]
    }
    new_state = {
      comments: [
        { "author" => "alice@example.com", "body" => "First", "created_at" => "2025-12-04T10:00:00Z" },
        { "author" => "bob@example.com", "body" => "Second", "created_at" => "2025-12-04T11:00:00Z" }
      ]
    }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 1, comment_changes.length
  end

  test "comment matching requires all three fields to match" do
    old_state = {
      comments: [
        { author: "alice@example.com", body: "Test", created_at: "2025-12-04T10:00:00Z" }
      ]
    }
    new_state = {
      comments: [
        { author: "alice@example.com", body: "Test", created_at: "2025-12-04T10:00:00Z" },
        { author: "alice@example.com", body: "Test", created_at: "2025-12-04T11:00:00Z" },
        { author: "bob@example.com", body: "Test", created_at: "2025-12-04T10:00:00Z" },
        { author: "alice@example.com", body: "Different", created_at: "2025-12-04T10:00:00Z" }
      ]
    }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    comment_changes = changes.select { |c| c.is_a?(Beads::Changes::CommentAddition) }
    assert_equal 3, comment_changes.length
  end

  # ====================
  # Multiple Changes
  # ====================

  test "detects multiple changes when multiple fields changed" do
    old_state = { title: "Old", status: "open", assignee: nil }
    new_state = { title: "New", status: "closed", assignee: "alice@example.com" }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 3, changes.length

    change_types = changes.map(&:class)
    assert_includes change_types, Beads::Changes::StatusChange
    assert_includes change_types, Beads::Changes::AssignmentChange
    assert_includes change_types, Beads::Changes::TitleChange
  end

  test "detects all types of changes simultaneously" do
    old_state = {
      status: "open",
      assignee: nil,
      title: "Old Title",
      description: "Old description",
      priority: 2,
      labels: ["bug"],
      comments: []
    }
    new_state = {
      status: "in_progress",
      assignee: "alice@example.com",
      title: "New Title",
      description: "New description",
      priority: 0,
      labels: ["bug", "p0"],
      comments: [
        { author: "alice@example.com", body: "Comment", created_at: "2025-12-04T10:00:00Z" }
      ]
    }

    detector = Beads::ChangeDetector.new(
      old_state: old_state,
      new_state: new_state,
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 7, changes.length

    change_types = changes.map(&:class)
    assert_includes change_types, Beads::Changes::StatusChange
    assert_includes change_types, Beads::Changes::AssignmentChange
    assert_includes change_types, Beads::Changes::TitleChange
    assert_includes change_types, Beads::Changes::DescriptionChange
    assert_includes change_types, Beads::Changes::PriorityChange
    assert_includes change_types, Beads::Changes::LabelsChange
    assert_includes change_types, Beads::Changes::CommentAddition
  end

  # ====================
  # Edge Cases
  # ====================

  test "handles empty old_state as empty hash" do
    detector = Beads::ChangeDetector.new(
      old_state: nil,
      new_state: { title: "Test", status: "open" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert changes.any?
  end

  test "handles missing keys in old_state" do
    detector = Beads::ChangeDetector.new(
      old_state: {},
      new_state: { title: "Test", status: "open", assignee: "alice@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    change_types = changes.map(&:class)
    assert_includes change_types, Beads::Changes::TitleChange
    assert_includes change_types, Beads::Changes::StatusChange
    assert_includes change_types, Beads::Changes::AssignmentChange
  end

  test "handles empty strings vs nil" do
    detector = Beads::ChangeDetector.new(
      old_state: { title: "" },
      new_state: { title: nil },
      issue: mock_issue
    )

    changes = detector.detect_changes
    title_changes = changes.select { |c| c.is_a?(Beads::Changes::TitleChange) }
    assert_equal 0, title_changes.length
  end

  test "handles hash with string keys in old_state" do
    detector = Beads::ChangeDetector.new(
      old_state: { "status" => "open", "title" => "Test" },
      new_state: { status: "closed", title: "Test" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::StatusChange, changes.first
  end

  test "handles mixed symbol and string keys" do
    detector = Beads::ChangeDetector.new(
      old_state: { "status" => "open", :assignee => nil },
      new_state: { status: "open", assignee: "alice@example.com" },
      issue: mock_issue
    )

    changes = detector.detect_changes
    assert_equal 1, changes.length
    assert_instance_of Beads::Changes::AssignmentChange, changes.first
  end

  private

  def mock_issue
    OpenStruct.new(id: "fizzy-test", title: "Test Issue")
  end
end
