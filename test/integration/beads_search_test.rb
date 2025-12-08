require "test_helper"

class BeadsSearchTest < ActionDispatch::IntegrationTest
  setup do
    @account = accounts(:default)
    @user = users(:david)
    @board = boards(:tasks)

    # Make board beads-enabled with a test repo
    test_repo = Rails.root.join("tmp", "test_beads_repo_#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(test_repo.join(".beads"))
    @board.update!(repo_path: test_repo.to_s)

    untenanted { sign_in_as @user }
  end

  teardown do
    # Clean up test repo
    FileUtils.rm_rf(@board.repo_path) if @board.repo_path&.start_with?(Rails.root.join("tmp").to_s)
  end

  test "search returns beads issues when board is beads-enabled" do
    # Mock the beads search response
    beads_client = @board.beads_client
    search_result = [
      {
        "id" => "test-123",
        "title" => "Test beads issue",
        "description" => "This is a test description",
        "status" => "open",
        "priority" => 1,
        "issue_type" => "task",
        "created_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601
      }
    ]

    beads_client.stub :search, search_result do
      get search_path(q: "test", script_name: "/#{@account.external_account_id}")

      assert_response :success
      assert_select ".search__title", text: /Test beads issue/
    end
  end

  test "search handles errors from beads gracefully" do
    # Mock beads client to raise an error
    beads_client = @board.beads_client
    beads_client.stub :search, -> (*) { raise BeadsClient::Error, "Connection failed" } do
      get search_path(q: "test", script_name: "/#{@account.external_account_id}")

      assert_response :success
      # Should show no results instead of crashing
      assert_select ".search__empty"
    end
  end
end
