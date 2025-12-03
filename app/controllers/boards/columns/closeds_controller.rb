class Boards::Columns::ClosedsController < ApplicationController
  include BoardScoped

  def show
    if @board.beads_enabled?
      # Show beads issues with status closed
      issues = @board.beads_client.list(status: "closed")
      @beads_cards = issues.map { |data| BeadsIssue.new(data) }
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @board.cards.closed.recently_closed_first.preloaded
      fresh_when etag: @page.records
    end
  end
end
