# frozen_string_literal: true

require "test_helper"

class BeadsBridgeTest < ActiveSupport::TestCase
  setup do
    @account = accounts("37s")
    @creator = users("david")

    # Create a temporary test directory for beads repo
    @test_repo_path = "/tmp/test-beads-#{SecureRandom.hex(8)}"
    FileUtils.mkdir_p(@test_repo_path)
    FileUtils.mkdir_p("#{@test_repo_path}/.beads")

    @board = Board.create!(
      account: @account,
      creator: @creator,
      name: "Test Board",
      repo_path: @test_repo_path
    )
    @bridge = BeadsBridge.new(@board)

    # Mock the beads client
    @mock_client = mock("beads_client")
    @board.stubs(:beads_client).returns(@mock_client)

    # Mock list_comments to return empty array by default
    @mock_client.stubs(:list_comments).returns([])
  end

  teardown do
    # Clean up test directory
    FileUtils.rm_rf(@test_repo_path) if @test_repo_path && Dir.exist?(@test_repo_path)
  end

  # ====================
  # Create Mutation Tests
  # ====================

  test "creates published event on create mutation" do
    issue_data = {
      id: "fizzy-test",
      title: "New issue",
      description: "Test description",
      status: "open",
      priority: 2,
      issue_type: "task",
      assignee: nil,
      labels: [],
      comments: [],
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601,
      closed_at: nil
    }

    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = {
      "Type" => "create",
      "IssueID" => "fizzy-test",
      "Timestamp" => Time.current.iso8601
    }

    assert_difference "Event.where(action: 'beads_issue_published').count", 1 do
      assert_difference "BeadsIssueState.count", 1 do
        @bridge.send(:process_mutation, mutation)
      end
    end

    event = Event.where(action: "beads_issue_published").last
    assert_equal "fizzy-test", event.beads_issue_id
    assert_equal "BeadsIssue", event.eventable_type

    state = BeadsIssueState.find_by(issue_id: "fizzy-test")
    assert_equal "open", state.parsed_snapshot[:status]
  end

  test "creates cache entry on create mutation" do
    issue_data = mock_issue_data("fizzy-test", status: "open", title: "New issue")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = create_mutation("fizzy-test")

    assert_difference "BeadsIssueState.count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    state = BeadsIssueState.find_by(board: @board, issue_id: "fizzy-test")
    assert_not_nil state
    assert_equal "open", state.parsed_snapshot[:status]
    assert_equal "New issue", state.parsed_snapshot[:title]
  end

  # ====================
  # Status Change Tests
  # ====================

  test "creates closed event when status changes to closed" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Bug", assignee: nil }
    )

    issue_data = mock_issue_data("fizzy-test", status: "closed", title: "Bug")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_closed').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_closed").last
    assert_equal "open", event.old_status
    assert_equal "closed", event.new_status
    assert_equal "fizzy-test", event.beads_issue_id
  end

  test "creates started event when status changes to in_progress" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Feature" }
    )

    issue_data = mock_issue_data("fizzy-test", status: "in_progress", title: "Feature")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_started').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_started").last
    assert_equal "open", event.old_status
    assert_equal "in_progress", event.new_status
  end

  test "creates blocked event when status changes to blocked" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "in_progress", title: "Task" }
    )

    issue_data = mock_issue_data("fizzy-test", status: "blocked", title: "Task")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_blocked').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_blocked").last
    assert_equal "in_progress", event.old_status
    assert_equal "blocked", event.new_status
  end

  test "creates reopened event when status changes from closed to open" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "closed", title: "Bug" }
    )

    issue_data = mock_issue_data("fizzy-test", status: "open", title: "Bug")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_reopened').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_reopened").last
    assert_equal "closed", event.old_status
    assert_equal "open", event.new_status
  end

  # ====================
  # Assignment Change Tests
  # ====================

  test "creates assigned event when assignee is set" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Task", assignee: nil }
    )

    issue_data = mock_issue_data("fizzy-test", assignee: "alice@example.com")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_assigned').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_assigned").last
    assert_nil event.old_assignee
    assert_equal "alice@example.com", event.new_assignee
  end

  test "creates unassigned event when assignee is removed" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Task", assignee: "alice@example.com" }
    )

    issue_data = mock_issue_data("fizzy-test", assignee: nil)
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_unassigned').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_unassigned").last
    assert_equal "alice@example.com", event.old_assignee
    assert_nil event.new_assignee
  end

  test "creates assigned event when assignee changes from one email to another" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Task", assignee: "alice@example.com" }
    )

    issue_data = mock_issue_data("fizzy-test", assignee: "bob@example.com")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_issue_assigned').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_issue_assigned").last
    assert_equal "alice@example.com", event.old_assignee
    assert_equal "bob@example.com", event.new_assignee
  end

  # ====================
  # Comment Addition Tests
  # ====================

  test "creates comment event when new comment detected" do
    skip "Test infrastructure issue - see fizzy-0oi. BeadsIssue.new doesn't parse comments from hash. Unskip when investigating."

    old_comments = [
      { author: "alice@example.com", body: "First comment", created_at: "2025-12-04T10:00:00Z" }
    ]
    new_comments = old_comments + [
      { author: "bob@example.com", body: "Second comment", created_at: "2025-12-04T11:00:00Z" }
    ]

    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Task", comments: old_comments }
    )

    issue_data = mock_issue_data("fizzy-test", comments: new_comments)
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)
    @mock_client.stubs(:list_comments).with("fizzy-test").returns(new_comments)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_comment_created').count", 1 do
      @bridge.send(:process_mutation, mutation)
    end

    event = Event.where(action: "beads_comment_created").last
    assert_equal "bob@example.com", event.comment_author
    assert_equal "Second comment", event.comment_excerpt
  end

  test "creates multiple comment events when multiple comments added" do
    skip "Test infrastructure issue - see fizzy-0oi. BeadsIssue.new doesn't parse comments from hash. Unskip when investigating."

    old_comments = [
      { author: "alice@example.com", body: "First", created_at: "2025-12-04T10:00:00Z" }
    ]
    new_comments = old_comments + [
      { author: "bob@example.com", body: "Second", created_at: "2025-12-04T11:00:00Z" },
      { author: "charlie@example.com", body: "Third", created_at: "2025-12-04T12:00:00Z" }
    ]

    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Task", comments: old_comments }
    )

    issue_data = mock_issue_data("fizzy-test", comments: new_comments)
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)
    @mock_client.stubs(:list_comments).with("fizzy-test").returns(new_comments)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(action: 'beads_comment_created').count", 2 do
      @bridge.send(:process_mutation, mutation)
    end

    events = Event.where(action: "beads_comment_created").last(2)
    authors = events.map(&:comment_author)
    assert_includes authors, "bob@example.com"
    assert_includes authors, "charlie@example.com"
  end

  # ====================
  # Multiple Changes Tests
  # ====================

  test "creates multiple events when multiple fields change" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", assignee: nil, title: "Task" }
    )

    issue_data = mock_issue_data(
      "fizzy-test",
      status: "in_progress",
      assignee: "bob@example.com",
      title: "Task"
    )
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(eventable_type: 'BeadsIssue').count", 2 do
      @bridge.send(:process_mutation, mutation)
    end

    events = Event.where(eventable_type: "BeadsIssue").last(2)
    actions = events.map(&:action)
    assert_includes actions, "beads_issue_started"
    assert_includes actions, "beads_issue_assigned"
  end

  test "creates events for status change, assignment, and comment simultaneously" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: {
        status: "open",
        assignee: nil,
        title: "Task",
        comments: []
      }
    )

    new_comments = [
      { author: "bob@example.com", body: "Starting work", created_at: "2025-12-04T11:00:00Z" }
    ]

    issue_data = mock_issue_data(
      "fizzy-test",
      status: "in_progress",
      assignee: "bob@example.com",
      title: "Task",
      comments: new_comments
    )
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)
    @mock_client.stubs(:list_comments).with("fizzy-test").returns(new_comments)

    mutation = update_mutation("fizzy-test")

    assert_difference "Event.where(eventable_type: 'BeadsIssue').count", 3 do
      @bridge.send(:process_mutation, mutation)
    end

    events = Event.where(eventable_type: "BeadsIssue").last(3)
    actions = events.map(&:action)
    assert_includes actions, "beads_issue_started"
    assert_includes actions, "beads_issue_assigned"
    assert_includes actions, "beads_comment_created"
  end

  # ====================
  # No Changes Test
  # ====================

  test "does not create event when nothing changed" do
    cached_state = {
      status: "open",
      assignee: "alice@example.com",
      title: "Bug fix",
      description: "Fix the bug",
      priority: 2,
      labels: ["bug"],
      comments: []
    }

    create_cached_state(issue_id: "fizzy-test", state: cached_state)

    issue_data = mock_issue_data(
      "fizzy-test",
      status: "open",
      assignee: "alice@example.com",
      title: "Bug fix",
      description: "Fix the bug",
      priority: 2,
      labels: ["bug"],
      comments: []
    )
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_no_difference "Event.where(eventable_type: 'BeadsIssue').count" do
      @bridge.send(:process_mutation, mutation)
    end
  end

  # ====================
  # Delete Mutation Test
  # ====================

  test "removes cache entry on delete mutation" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "closed", title: "Old issue" }
    )

    mutation = {
      "Type" => "delete",
      "IssueID" => "fizzy-test",
      "Timestamp" => Time.current.iso8601
    }

    assert_difference "BeadsIssueState.count", -1 do
      @bridge.send(:process_mutation, mutation)
    end

    assert_nil BeadsIssueState.find_by(board: @board, issue_id: "fizzy-test")
  end

  test "delete mutation preserves existing events" do
    skip "Test infrastructure issue - see fizzy-0oi. Mock expectation mismatch when Event loads eventable. Unskip when investigating."

    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "closed", title: "Old issue" }
    )

    # Create an event for this issue
    Event.create!(
      board: @board,
      creator: @creator,
      eventable_type: "BeadsIssue",
      eventable_id: @bridge.send(:beads_issue_to_uuid, "fizzy-test"),
      action: "beads_issue_published",
      beads_issue_id: "fizzy-test"
    )

    mutation = {
      "Type" => "delete",
      "IssueID" => "fizzy-test",
      "Timestamp" => Time.current.iso8601
    }

    # Stub show in case Event tries to load the eventable
    # Use mock_issue_data to return a valid issue (though it's deleted)
    @mock_client.stubs(:show).with("fizzy-test").returns(
      mock_issue_data("fizzy-test", status: "closed", title: "Old issue")
    )

    assert_no_difference "Event.where(beads_issue_id: 'fizzy-test').count" do
      @bridge.send(:process_mutation, mutation)
    end
  end

  # ====================
  # Edge Cases
  # ====================

  test "handles missing cache state by treating as create" do
    # No cached state exists
    issue_data = mock_issue_data("fizzy-test", status: "open", title: "New issue")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    assert_difference "BeadsIssueState.count", 1 do
      assert_difference "Event.where(action: 'beads_issue_published').count", 1 do
        @bridge.send(:process_mutation, mutation)
      end
    end
  end

  test "handles corrupted cache by rebuilding" do
    # Create corrupted cache
    state = BeadsIssueState.create!(
      board: @board,
      issue_id: "fizzy-test",
      snapshot: "invalid json {{{",
      synced_at: 1.hour.ago
    )

    issue_data = mock_issue_data("fizzy-test", status: "open", title: "Recovered issue")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")

    # Should delete corrupted cache and create new one
    assert_no_difference "BeadsIssueState.count" do
      assert_difference "Event.where(action: 'beads_issue_published').count", 1 do
        @bridge.send(:process_mutation, mutation)
      end
    end

    # Cache should now have valid data (find by issue_id since old record was destroyed)
    new_state = BeadsIssueState.find_by(board: @board, issue_id: "fizzy-test")
    assert_equal "open", new_state.parsed_snapshot[:status]
  end

  test "updates cache after processing changes" do
    create_cached_state(
      issue_id: "fizzy-test",
      state: { status: "open", title: "Original" }
    )

    issue_data = mock_issue_data("fizzy-test", status: "closed", title: "Updated")
    @mock_client.stubs(:show).with("fizzy-test").returns(issue_data)

    mutation = update_mutation("fizzy-test")
    @bridge.send(:process_mutation, mutation)

    state = BeadsIssueState.find_by(board: @board, issue_id: "fizzy-test")
    assert_equal "closed", state.parsed_snapshot[:status]
    assert_equal "Updated", state.parsed_snapshot[:title]
  end

  private

  def create_mutation(issue_id)
    {
      "Type" => "create",
      "IssueID" => issue_id,
      "Timestamp" => Time.current.iso8601
    }
  end

  def update_mutation(issue_id)
    {
      "Type" => "update",
      "IssueID" => issue_id,
      "Timestamp" => Time.current.iso8601
    }
  end

  def create_cached_state(issue_id:, state:)
    # Merge with defaults to match what mock_issue_data produces
    # Use fixed timestamp to avoid timing issues
    fixed_time = "2025-12-04T00:00:00Z"
    default_state = {
      id: issue_id,
      title: "Test Issue",
      description: "Test description",
      status: "open",
      priority: 2,
      issue_type: "task",
      assignee: nil,
      labels: [],
      comments: [],
      created_at: fixed_time,
      updated_at: fixed_time,
      closed_at: nil
    }

    full_state = default_state.merge(state)

    BeadsIssueState.create!(
      board: @board,
      issue_id: issue_id,
      snapshot: full_state.to_json,
      synced_at: 1.hour.ago
    )
  end

  def mock_issue_data(issue_id, **overrides)
    # Use fixed timestamp to match create_cached_state
    fixed_time = "2025-12-04T00:00:00Z"
    defaults = {
      id: issue_id,
      title: "Test Issue",
      description: "Test description",
      status: "open",
      priority: 2,
      issue_type: "task",
      assignee: nil,
      labels: [],
      comments: [],
      created_at: fixed_time,
      updated_at: fixed_time,
      closed_at: nil
    }
    defaults.merge(overrides)
  end
end
