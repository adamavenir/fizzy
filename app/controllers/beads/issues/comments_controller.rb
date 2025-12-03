class Beads::Issues::CommentsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_board
  before_action :set_issue

  def create
    return head :bad_request unless @board&.beads_enabled?

    client = @board.beads_client
    client.add_comment(
      @issue.id,
      text: params[:body],
      author: Current.user.identity.email_address
    )

    # Reload to get fresh comments
    data = @board.beads_client.show(@issue.id)
    @issue = BeadsIssue.new(data)
    @issue.board = @board

    # Render turbo stream to update comments and clear form
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(dom_id(@issue, :messages), partial: "cards/messages", locals: { card: @issue }),
          turbo_stream.replace(dom_id(@issue, :new_comment), partial: "cards/comments/new", locals: { card: @issue })
        ]
      end
      format.html { redirect_to issue_path(board_id: @board.id, issue_id: @issue.id), notice: "Comment added" }
    end
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
