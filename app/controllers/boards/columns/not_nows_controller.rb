class Boards::Columns::NotNowsController < ApplicationController
  include BoardScoped

  def show
    if @board.beads_enabled?
      # Show beads issues with fizzy:not-now label
      issues = @board.beads_client.list(status: "open", labels: ["fizzy:not-now"])
      @beads_cards = issues.map do |data|
        issue = BeadsIssue.new(data)
        issue.board = @board
        issue
      end
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @board.cards.postponed.reverse_chronologically.with_golden_first.preloaded
      fresh_when etag: @page.records
    end
  end
end
