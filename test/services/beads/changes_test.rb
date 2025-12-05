# frozen_string_literal: true

require "test_helper"

class Beads::ChangesTest < ActiveSupport::TestCase
  # StatusChange tests
  test "StatusChange returns correct event action for closed" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "closed")
    assert_equal "beads_issue_closed", change.event_action
  end

  test "StatusChange returns correct event action for reopened" do
    change = Beads::Changes::StatusChange.new(from: "closed", to: "open")
    assert_equal "beads_issue_reopened", change.event_action
  end

  test "StatusChange returns correct event action for started from open" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "in_progress")
    assert_equal "beads_issue_started", change.event_action
  end

  test "StatusChange returns correct event action for started from open to open" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "open")
    assert_equal "beads_issue_started", change.event_action
  end

  test "StatusChange returns correct event action for blocked" do
    change = Beads::Changes::StatusChange.new(from: "in_progress", to: "blocked")
    assert_equal "beads_issue_blocked", change.event_action
  end

  test "StatusChange returns generic action for unknown status" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "unknown")
    assert_equal "beads_issue_status_changed", change.event_action
  end

  test "StatusChange includes old and new status in particulars" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "closed")
    assert_equal "open", change.event_particulars[:old_status]
    assert_equal "closed", change.event_particulars[:new_status]
  end

  test "StatusChange is notifiable" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "closed")
    assert change.notifiable?
  end

  test "StatusChange includes actor when provided" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "closed", actor: "alice@example.com")
    assert_equal "alice@example.com", change.actor_email
  end

  test "StatusChange actor is nil when not provided" do
    change = Beads::Changes::StatusChange.new(from: "open", to: "closed")
    assert_nil change.actor_email
  end

  # AssignmentChange tests
  test "AssignmentChange returns assigned action when assigning" do
    change = Beads::Changes::AssignmentChange.new(from: nil, to: "alice@example.com")
    assert_equal "beads_issue_assigned", change.event_action
  end

  test "AssignmentChange returns unassigned action when unassigning" do
    change = Beads::Changes::AssignmentChange.new(from: "alice@example.com", to: nil)
    assert_equal "beads_issue_unassigned", change.event_action
  end

  test "AssignmentChange returns assigned action when reassigning" do
    change = Beads::Changes::AssignmentChange.new(from: "alice@example.com", to: "bob@example.com")
    assert_equal "beads_issue_assigned", change.event_action
  end

  test "AssignmentChange includes old and new assignee in particulars" do
    change = Beads::Changes::AssignmentChange.new(from: "alice@example.com", to: "bob@example.com")
    assert_equal "alice@example.com", change.event_particulars[:old_assignee]
    assert_equal "bob@example.com", change.event_particulars[:new_assignee]
  end

  test "AssignmentChange is notifiable when assigning" do
    change = Beads::Changes::AssignmentChange.new(from: nil, to: "alice@example.com")
    assert change.notifiable?
  end

  test "AssignmentChange is not notifiable when unassigning" do
    change = Beads::Changes::AssignmentChange.new(from: "alice@example.com", to: nil)
    assert_not change.notifiable?
  end

  test "AssignmentChange actor is the new assignee when assigning" do
    change = Beads::Changes::AssignmentChange.new(from: nil, to: "alice@example.com")
    assert_equal "alice@example.com", change.actor_email
  end

  test "AssignmentChange actor is the old assignee when unassigning" do
    change = Beads::Changes::AssignmentChange.new(from: "alice@example.com", to: nil)
    assert_equal "alice@example.com", change.actor_email
  end

  # TitleChange tests
  test "TitleChange returns correct event action" do
    change = Beads::Changes::TitleChange.new(from: "Old title", to: "New title")
    assert_equal "beads_issue_title_changed", change.event_action
  end

  test "TitleChange includes old and new title in particulars" do
    change = Beads::Changes::TitleChange.new(from: "Old", to: "New")
    assert_equal "Old", change.event_particulars[:old_title]
    assert_equal "New", change.event_particulars[:new_title]
  end

  test "TitleChange is not notifiable" do
    change = Beads::Changes::TitleChange.new(from: "Old", to: "New")
    assert_not change.notifiable?
  end

  test "TitleChange actor is nil" do
    change = Beads::Changes::TitleChange.new(from: "Old", to: "New")
    assert_nil change.actor_email
  end

  # DescriptionChange tests
  test "DescriptionChange returns correct event action" do
    change = Beads::Changes::DescriptionChange.new(from: "Old", to: "New")
    assert_equal "beads_issue_description_changed", change.event_action
  end

  test "DescriptionChange truncates long descriptions in particulars" do
    long_text = "a" * 300
    change = Beads::Changes::DescriptionChange.new(from: long_text, to: "New")
    assert_equal 200, change.event_particulars[:old_description].length
    assert_equal "New", change.event_particulars[:new_description]
  end

  test "DescriptionChange handles nil descriptions" do
    change = Beads::Changes::DescriptionChange.new(from: nil, to: "New")
    assert_nil change.event_particulars[:old_description]
    assert_equal "New", change.event_particulars[:new_description]
  end

  test "DescriptionChange is not notifiable" do
    change = Beads::Changes::DescriptionChange.new(from: "Old", to: "New")
    assert_not change.notifiable?
  end

  test "DescriptionChange actor is nil" do
    change = Beads::Changes::DescriptionChange.new(from: "Old", to: "New")
    assert_nil change.actor_email
  end

  # PriorityChange tests
  test "PriorityChange returns correct event action" do
    change = Beads::Changes::PriorityChange.new(from: 1, to: 0)
    assert_equal "beads_issue_priority_changed", change.event_action
  end

  test "PriorityChange includes old and new priority in particulars" do
    change = Beads::Changes::PriorityChange.new(from: 2, to: 0)
    assert_equal 2, change.event_particulars[:old_priority]
    assert_equal 0, change.event_particulars[:new_priority]
  end

  test "PriorityChange is not notifiable" do
    change = Beads::Changes::PriorityChange.new(from: 1, to: 0)
    assert_not change.notifiable?
  end

  test "PriorityChange actor is nil" do
    change = Beads::Changes::PriorityChange.new(from: 1, to: 0)
    assert_nil change.actor_email
  end

  test "PriorityChange handles nil priorities" do
    change = Beads::Changes::PriorityChange.new(from: nil, to: 2)
    assert_nil change.event_particulars[:old_priority]
    assert_equal 2, change.event_particulars[:new_priority]
  end

  # LabelsChange tests
  test "LabelsChange returns correct event action" do
    change = Beads::Changes::LabelsChange.new(added: ["bug"], removed: [])
    assert_equal "beads_issue_labels_changed", change.event_action
  end

  test "LabelsChange includes added and removed labels in particulars" do
    change = Beads::Changes::LabelsChange.new(added: ["bug"], removed: ["feature"])
    assert_equal ["bug"], change.event_particulars[:labels_added]
    assert_equal ["feature"], change.event_particulars[:labels_removed]
  end

  test "LabelsChange handles empty arrays" do
    change = Beads::Changes::LabelsChange.new(added: [], removed: [])
    assert_equal [], change.event_particulars[:labels_added]
    assert_equal [], change.event_particulars[:labels_removed]
  end

  test "LabelsChange is not notifiable" do
    change = Beads::Changes::LabelsChange.new(added: ["bug"], removed: [])
    assert_not change.notifiable?
  end

  test "LabelsChange actor is nil" do
    change = Beads::Changes::LabelsChange.new(added: ["bug"], removed: [])
    assert_nil change.actor_email
  end

  # CommentAddition tests
  test "CommentAddition returns correct event action" do
    comment = { author: "alice@example.com", body: "Comment", created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)
    assert_equal "beads_comment_created", change.event_action
  end

  test "CommentAddition includes comment metadata in particulars" do
    comment = { author: "alice@example.com", body: "Test comment", created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)
    particulars = change.event_particulars

    assert_equal "alice@example.com", particulars[:comment_author]
    assert_equal "2025-12-04T12:00:00Z", particulars[:comment_created_at]
    assert_equal "Test comment", particulars[:comment_excerpt]
    assert_not_nil particulars[:comment_body_hash]
  end

  test "CommentAddition truncates long comment bodies in excerpt" do
    long_comment = { author: "alice@example.com", body: "a" * 300, created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(long_comment)
    assert_equal 200, change.event_particulars[:comment_excerpt].length
  end

  test "CommentAddition handles nil body" do
    comment = { author: "alice@example.com", body: nil, created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)
    assert_equal "", change.event_particulars[:comment_excerpt]
    assert_not_nil change.event_particulars[:comment_body_hash]
  end

  test "CommentAddition is notifiable" do
    comment = { author: "alice@example.com", body: "Comment", created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)
    assert change.notifiable?
  end

  test "CommentAddition actor is the comment author" do
    comment = { author: "alice@example.com", body: "Comment", created_at: "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)
    assert_equal "alice@example.com", change.actor_email
  end

  test "CommentAddition generates consistent hash for same body" do
    comment1 = { author: "alice@example.com", body: "Same comment", created_at: "2025-12-04T12:00:00Z" }
    comment2 = { author: "bob@example.com", body: "Same comment", created_at: "2025-12-04T13:00:00Z" }

    change1 = Beads::Changes::CommentAddition.new(comment1)
    change2 = Beads::Changes::CommentAddition.new(comment2)

    assert_equal change1.event_particulars[:comment_body_hash],
                 change2.event_particulars[:comment_body_hash]
  end

  test "CommentAddition generates different hash for different body" do
    comment1 = { author: "alice@example.com", body: "Comment 1", created_at: "2025-12-04T12:00:00Z" }
    comment2 = { author: "alice@example.com", body: "Comment 2", created_at: "2025-12-04T12:00:00Z" }

    change1 = Beads::Changes::CommentAddition.new(comment1)
    change2 = Beads::Changes::CommentAddition.new(comment2)

    assert_not_equal change1.event_particulars[:comment_body_hash],
                     change2.event_particulars[:comment_body_hash]
  end

  test "CommentAddition deep symbolizes keys" do
    comment = { "author" => "alice@example.com", "body" => "Comment", "created_at" => "2025-12-04T12:00:00Z" }
    change = Beads::Changes::CommentAddition.new(comment)

    particulars = change.event_particulars
    assert_equal "alice@example.com", particulars[:comment_author]
    assert_equal "Comment", particulars[:comment_excerpt]
  end
end
