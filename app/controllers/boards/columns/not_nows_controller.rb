class Boards::Columns::NotNowsController < ApplicationController
  include BoardScoped

  def show
    if @board.beads_enabled?
      # Use BeadsCardQuery with a temporary Column-like object to get proper filtering
      column_stub = OpenStruct.new(
        column_type: "fizzy_tag",
        beads_value: "fizzy:not-now"
      )
      @beads_cards = BeadsCardQuery.new(@board).for_column(column_stub)
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @board.cards.postponed.reverse_chronologically.with_golden_first.preloaded
      fresh_when etag: @page.records
    end
  end
end
