class Beads::Issues::ColumnsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def edit
    @card = @issue
    @columns = @board.columns.where(column_type: "beads_status").sorted

    fresh_when etag: [@issue, @columns]
  end

  private

  def set_board
    @board = Current.user.boards.find(params[:board_id])
  end

  def set_issue
    @issue = BeadsIssue.new(@board.beads_client.show(params[:issue_issue_id]))
    @issue.board = @board
  end
end
