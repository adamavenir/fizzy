class Beads::IssuesController < ApplicationController
  before_action :set_board
  before_action :set_issue, only: [:show, :edit, :update, :destroy]

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
    # Set creator to current user for draft cards
    @issue.instance_variable_set(:@creator, Current.user)
    @card = @issue
  end

  def create
    client = @board.beads_client

    # Extract params
    params_source = params[:issue] || params

    # Create issue in beads with actual user data
    # Pass email as actor for audit trail, and store in creator label for lookup
    creator_email = Current.user.identity.email_address
    result = client.create(
      title: params_source[:title],
      description: params_source[:description],
      labels: ["fizzy:maybe", "creator:#{creator_email}"],
      priority: 2,
      issue_type: "task",
      actor: creator_email
    )

    if params[:creation_type] == "add_another"
      redirect_to new_issue_path(board_id: @board), notice: "Card added"
    else
      redirect_to board_path(@board), notice: "Card added"
    end
  rescue BeadsClient::Error => e
    redirect_to board_path(@board), alert: "Failed to create card: #{e.message}"
  end

  def show
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

  def destroy
    client = @board.beads_client

    # Close the issue in beads
    client.close(@issue.id)

    redirect_to board_path(@board), notice: "Card deleted"
  rescue BeadsClient::Error => e
    redirect_to board_path(@board), alert: "Failed to delete card: #{e.message}"
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
