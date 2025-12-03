class Beads::Issues::WatchesController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def show
    @card = @issue
    @watching = false  # Beads doesn't track watching
  end

  def create
    # No-op for beads (could add label in future)
    redirect_to issue_path(board_id: @board.id, issue_id: @issue.id)
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def set_issue
      data = @board.beads_client.show(params[:issue_issue_id])
      @issue = BeadsIssue.new(data)
      @issue.board = @board
    end
end
