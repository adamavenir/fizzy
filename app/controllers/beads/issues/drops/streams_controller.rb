class Beads::Issues::Drops::StreamsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def create
    return head :bad_request unless @board&.beads_enabled?

    client = @board.beads_client

    # Remove any other fizzy labels
    @issue.labels&.each do |label|
      client.remove_label(@issue.id, label) if label.start_with?("fizzy:") && label != "fizzy:maybe"
    end

    # Add fizzy:maybe label and ensure status is open
    client.add_label(@issue.id, "fizzy:maybe")
    client.update(@issue.id, status: "open")

    head :ok
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
    end
end
