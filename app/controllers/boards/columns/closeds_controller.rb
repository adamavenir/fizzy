class Boards::Columns::ClosedsController < ApplicationController
  include BoardScoped

  def show
    if @board.beads_enabled?
      # Show beads issues with status closed, most recently closed first
      issues = @board.beads_client.list(status: "closed")
      @beads_cards = issues.map do |data|
        issue = BeadsIssue.new(data)
        issue.board = @board
        issue
      end.sort_by { |issue| issue.updated_at || Time.at(0) }.reverse
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @board.cards.closed.recently_closed_first.preloaded
      fresh_when etag: @page.records
    end
  end
end
