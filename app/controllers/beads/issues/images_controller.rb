class Beads::Issues::ImagesController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def create
    return head :bad_request unless @board&.beads_enabled?
    return head :unprocessable_entity unless params[:image].present?

    # Save image to .beads/images/
    images_dir = File.join(@board.repo_path, ".beads", "images")
    FileUtils.mkdir_p(images_dir)

    uploaded_file = params[:image]
    filename = "#{SecureRandom.hex(8)}#{File.extname(uploaded_file.original_filename)}"
    file_path = File.join(images_dir, filename)

    File.open(file_path, "wb") do |file|
      file.write(uploaded_file.read)
    end

    # Update description with cover image
    cover_line = "![cover](images/#{filename})\n"
    new_description = if @issue.cover_image_path
      # Replace existing cover
      @issue.description.sub(/^\!\[cover\]\(.+?\)\n?/, cover_line)
    else
      # Add new cover
      cover_line + (@issue.description || "")
    end

    @board.beads_client.update(@issue.id, description: new_description)

    redirect_to issue_path(board_id: @board.id, issue_id: @issue.id)
  end

  def destroy
    return head :bad_request unless @board&.beads_enabled?

    if @issue.cover_image_path
      # Remove image file
      image_file = File.join(@board.repo_path, ".beads", @issue.cover_image_path)
      File.delete(image_file) if File.exist?(image_file)

      # Remove cover line from description
      new_description = @issue.description_without_cover
      @board.beads_client.update(@issue.id, description: new_description)
    end

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
