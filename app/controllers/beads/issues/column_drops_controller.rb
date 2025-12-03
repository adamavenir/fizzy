class Beads::Issues::ColumnDropsController < ApplicationController
  before_action :set_board
  before_action :set_columns

  def create
    return head :bad_request unless @board&.beads_enabled?

    mover = BeadsCardMover.new(@board.beads_client)
    mover.move(params[:issue_id], @from_column, @to_column)

    head :ok
  rescue BeadsClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def set_columns
      @from_column = @board.columns.find(params[:from_column_id]) if params[:from_column_id]
      @to_column = @board.columns.find(params[:column_id])
    end
end
