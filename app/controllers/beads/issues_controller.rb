class Beads::IssuesController < ApplicationController
  before_action :set_board
  before_action :set_issue, only: [:show, :edit, :update]

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
