class Boards::ColumnsController < ApplicationController
  include BoardScoped

  before_action :set_column, only: %i[ show update destroy ]

  def show
    if @board.beads_enabled?
      @beads_cards = @column.beads_cards
      # Skip pagination for beads cards for now
      @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)
    else
      set_page_and_extract_portion_from @column.cards.active.latest.with_golden_first.preloaded
      fresh_when etag: @page.records
    end
  end

  def create
    @column = @board.columns.create!(column_params)
  end

  def update
    @column.update!(column_params)
  end

  def destroy
    @column.destroy
  end

  private
    def set_column
      @column = @board.columns.find(params[:id])
    end

    def column_params
      params.expect(column: [ :name, :color ])
    end
end
