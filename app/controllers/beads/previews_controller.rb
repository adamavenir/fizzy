class Beads::PreviewsController < ApplicationController
  def show
    prefix = params[:prefix]
    hash = params[:hash]

    board = Current.account.boards.find_by(beads_prefix: prefix)
    return head :not_found unless board

    full_id = "#{prefix}-#{hash}"

    begin
      issue_data = board.beads_client.show(full_id)
      @issue = BeadsIssue.new(issue_data)
      @issue.board = board

      render partial: "beads/previews/card", locals: { card: @issue }
    rescue BeadsClient::Error
      head :not_found
    end
  end
end
