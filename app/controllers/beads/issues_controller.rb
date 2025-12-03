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
  end

  def update
    client = @board.beads_client
    updates = {}

    updates[:title] = params[:title] if params[:title].present?

    # Preserve cover image line when updating description
    if params.key?(:description)
      cover_line = @issue.cover_image_path ? "![cover](#{@issue.cover_image_path})\n" : ""
      updates[:description] = cover_line + params[:description].to_s
    end

    updates[:priority] = params[:priority].to_i if params[:priority].present?
    updates[:issue_type] = params[:issue_type] if params[:issue_type].present?
    updates[:assignee] = params[:assignee] if params.key?(:assignee)

    if updates.any?
      client.update(@issue.id, **updates)
    end

    redirect_to issue_path(board_id: @board.id, issue_id: @issue.id), notice: "Issue updated"
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
