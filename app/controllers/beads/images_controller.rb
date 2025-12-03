class Beads::ImagesController < ApplicationController
  def show
    board = Current.user.boards.find(params[:board_id])
    image_path = File.join(board.repo_path, ".beads", "images", params[:path])

    if File.exist?(image_path)
      send_file image_path, disposition: "inline"
    else
      head :not_found
    end
  end
end
