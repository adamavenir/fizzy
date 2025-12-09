class Beads::ShortcutsController < ApplicationController
  def show
    prefix = params[:prefix]
    hash = params[:hash]

    board = Current.account.boards.find_by(beads_prefix: prefix)
    unless board
      redirect_to root_path, alert: "Board not found for prefix '#{prefix}'"
      return
    end

    full_id = "#{prefix}-#{hash}"

    begin
      issue_data = board.beads_client.show(full_id)
    rescue BeadsClient::Error => e
      redirect_to board_path(board), alert: "Card ##{hash} not found"
      return
    end

    redirect_to issue_path(board_id: board.id, issue_id: full_id)
  end

  def board
    prefix = params[:prefix]

    board = Current.account.boards.find_by(beads_prefix: prefix)
    unless board
      redirect_to root_path, alert: "Board not found for prefix '#{prefix}'"
      return
    end

    redirect_to board_path(board)
  end
end
