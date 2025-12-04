class Beads::Issues::Drops::ClosuresController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def create
    return head :bad_request unless @board&.beads_enabled?

    client = @board.beads_client

    # Remove any fizzy labels when closing
    @issue.labels&.each do |label|
      client.remove_label(@issue.id, label) if label.start_with?("fizzy:")
    end

    # Close the issue
    client.close(@issue.id)

    # Remove the card from the current view (it's now in Done)
    render turbo_stream: turbo_stream.remove(@issue.dom_id)
  rescue BeadsClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def set_issue
      issue_data = @board.beads_client.show(params[:issue_issue_id])
      @issue = BeadsIssue.new(issue_data)
      @issue.board = @board
    end
end
