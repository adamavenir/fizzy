require "test_helper"

class Beads::Issues::TaggingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as :kevin
    @account = accounts("37s")
    @creator = users("kevin")

    # Create a temporary test directory for beads repo
    @test_repo_path = "/tmp/test-beads-taggings-#{SecureRandom.hex(8)}"
    FileUtils.mkdir_p(@test_repo_path)
    FileUtils.mkdir_p("#{@test_repo_path}/.beads")

    # Initialize git repo (required by beads daemon)
    Dir.chdir(@test_repo_path) do
      system("git init --quiet")
      system("git config user.name 'Test User'")
      system("git config user.email 'test@example.com'")
    end

    @board = Board.create!(
      account: @account,
      creator: @creator,
      name: "Test Tagging Board",
      repo_path: @test_repo_path
    )

    @client = @board.beads_client

    # Create a test issue in beads
    @issue_data = @client.create(
      title: "Test issue for tagging",
      description: "Testing tag creation",
      labels: ["existing-label"]
    )
    @issue_id = @issue_data["id"]
  end

  teardown do
    # Clean up test issue
    @client.close(@issue_id) if @issue_id
    # Clean up test directory
    FileUtils.rm_rf(@test_repo_path) if @test_repo_path && Dir.exist?(@test_repo_path)
  end

  test "creating new tag adds it to beads and fizzy" do
    new_tag_title = "brand-new-tag-#{SecureRandom.hex(4)}"

    # Tag shouldn't exist in Fizzy yet
    assert_nil Current.account.tags.find_by(title: new_tag_title)

    # Issue shouldn't have this label yet
    issue = BeadsIssue.new(@client.show(@issue_id))
    assert_not_includes issue.labels, new_tag_title

    # Create the tag
    post issue_taggings_path(
      board_id: @board.id,
      issue_issue_id: @issue_id
    ), params: { tag_title: new_tag_title }, as: :turbo_stream

    assert_response :success

    # Tag should now exist in Fizzy
    assert Current.account.tags.find_by(title: new_tag_title),
      "Tag '#{new_tag_title}' should be created in Fizzy database"

    # Issue should have the label in beads
    updated_issue = BeadsIssue.new(@client.show(@issue_id))
    assert_includes updated_issue.labels, new_tag_title,
      "Issue should have '#{new_tag_title}' label in beads"
  end

  test "toggling existing tag removes it from beads" do
    existing_label = "existing-label"

    # Issue should have this label
    issue = BeadsIssue.new(@client.show(@issue_id))
    assert_includes issue.labels, existing_label

    # Toggle it off
    post issue_taggings_path(
      board_id: @board.id,
      issue_issue_id: @issue_id
    ), params: { tag_title: existing_label }, as: :turbo_stream

    assert_response :success

    # Issue should not have the label anymore
    updated_issue = BeadsIssue.new(@client.show(@issue_id))
    assert_not_includes updated_issue.labels, existing_label
  end

  test "changing priority creates tag in fizzy" do
    # Change priority to p0
    post issue_taggings_path(
      board_id: @board.id,
      issue_issue_id: @issue_id
    ), params: { tag_title: "p0" }, as: :turbo_stream

    assert_response :success

    # p0 tag should exist in Fizzy
    assert Current.account.tags.find_by(title: "p0")
  end
end
