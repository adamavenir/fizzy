class Beads::Issues::GoldnessesController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def create
    # Promote to golden (priority 0)
    @board.beads_client.update(@issue.id, priority: 0)
    redirect_to issue_path(board_id: @board.id, issue_id: @issue.id)
  end

  def destroy
    # Demote from golden (priority 2)
    @board.beads_client.update(@issue.id, priority: 2)
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
