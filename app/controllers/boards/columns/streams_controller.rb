class Boards::Columns::StreamsController < ApplicationController
  include BoardScoped

  def show
    if @board.beads_enabled?
      # Show beads issues with fizzy:maybe label (triage inbox)
      issues = @board.beads_client.list(status: "open", labels: ["fizzy:maybe"])
      @beads_cards = issues.map do |data|
        issue = BeadsIssue.new(data)
        issue.board = @board
        issue
      end
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @board.cards.awaiting_triage.latest.with_golden_first.preloaded
      fresh_when etag: @page.records
    end
  end
end
