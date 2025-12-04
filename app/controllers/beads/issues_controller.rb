class Beads::IssuesController < ApplicationController
  before_action :set_board
  before_action :set_issue, only: [:show, :edit, :update]

  def new
    # Create a temporary drafted BeadsIssue for the form (not persisted to beads yet)
    @issue = BeadsIssue.new(
      id: "draft-#{SecureRandom.hex(4)}",
      title: "",
      description: "",
      status: "draft",
      labels: ["fizzy:maybe"],
      priority: 2,
      issue_type: "task",
      created_at: Time.current,
      updated_at: Time.current
    )
    @issue.board = @board
    @card = @issue
  end

  def create
    client = @board.beads_client

    # Extract params
    params_source = params[:issue] || params

    # Create issue in beads with actual user data
    result = client.create(
      title: params_source[:title],
      description: params_source[:description],
      labels: ["fizzy:maybe"],
      priority: 2,
      issue_type: "task",
      actor: Current.user.name
    )

    # Redirect to the new issue
    redirect_to issue_path(board_id: @board, issue_id: result["id"])
  rescue BeadsClient::Error => e
    redirect_to board_path(@board), alert: "Failed to create card: #{e.message}"
  end

  def show
    respond_to do |format|
      format.html
      format.json { render json: @issue.as_json }
    end
  end

  def edit
    # Render inline edit form (turbo_frame)
    @card = @issue
    render "cards/edit"
  end

  def update
    client = @board.beads_client

    # Handle form params (could be :issue or direct params)
    params_source = params[:issue] || params
    updates = {}

    updates[:title] = params_source[:title] if params_source[:title].present?

    # Preserve cover image line when updating description
    if params_source.key?(:description)
      cover_line = @issue.cover_image_path ? "![cover](#{@issue.cover_image_path})\n" : ""
      updates[:description] = cover_line + params_source[:description].to_s
    end

    if updates.any?
      client.update(@issue.id, **updates)
    end

    # Reload for turbo_stream response
    data = client.show(@issue.id)
    @issue = BeadsIssue.new(data)
    @issue.board = @board
    @card = @issue
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id]) if params[:board_id]
    end

    def set_issue
      return unless @board&.beads_enabled?
      data = @board.beads_client.show(params[:issue_id])
      @issue = BeadsIssue.new(data)
      @issue.board = @board
    end
end
