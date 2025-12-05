class Beads::Issues::ColumnDropsController < ApplicationController
  before_action :set_board
  before_action :set_issue
  before_action :set_target_column

  def create
    return head :bad_request unless @board&.beads_enabled?

    client = @board.beads_client

    # Remove any fizzy: labels (moving out of triage)
    @issue.labels&.each do |label|
      client.remove_label(@issue.id, label) if label.start_with?("fizzy:")
    end

    # Set the target status
    if @target_column.beads_value == "closed"
      client.close(@issue.id)
    else
      client.update(@issue.id, status: @target_column.beads_value)
    end

    # Reload the issue with updated data
    data = client.show(@issue.id)
    @issue = BeadsIssue.new(data)
    @issue.board = @board
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

    def set_target_column
      @target_column = @board.columns.find(params[:column_id])
    end
end
