class Beads::IssuesController < ApplicationController
  before_action :set_board
  before_action :set_issue, only: [:show]

  def show
    render json: @issue.as_json
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id]) if params[:board_id]
    end

    def set_issue
      return unless @board&.beads_enabled?
      data = @board.beads_client.show(params[:issue_id])
      @issue = BeadsIssue.new(data)
    end
end
