class Beads::Issues::Drops::NotNowsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def create
    return head :bad_request unless @board&.beads_enabled?

    client = @board.beads_client

    # Remove any other fizzy labels
    @issue.labels&.each do |label|
      client.remove_label(@issue.id, label) if label.start_with?("fizzy:") && label != "fizzy:not-now"
    end

    # Add fizzy:not-now label and ensure status is open
    client.add_label(@issue.id, "fizzy:not-now")
    client.update(@issue.id, status: "open")

    # Reload and refresh the card container
    reload_issue
    @card = @issue
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

    def reload_issue
      issue_data = @board.beads_client.show(@issue.id)
      @issue = BeadsIssue.new(issue_data)
      @issue.board = @board
    end
end
