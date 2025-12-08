class SearchesController < ApplicationController
  include Turbo::DriveHelper

  def show
    query = params[:q]

    # First, try to find a card by ID
    if card = Current.user.accessible_cards.find_by_id(query)
      @card = card
      return
    end

    # Determine which boards to search
    has_regular_boards = Current.user.boards.any? { |b| !b.beads_enabled? }
    has_beads_boards = Current.user.has_beads_boards?

    # If only regular boards, use original search (returns ActiveRecord relation)
    if has_regular_boards && !has_beads_boards
      set_page_and_extract_portion_from Current.user.search(query)
      @recent_search_queries = Current.user.search_queries.order(updated_at: :desc).limit(10)
      return
    end

    # If only beads boards or mixed, merge results
    results = []

    if has_beads_boards
      beads_results = Current.user.search_beads(query)
      results.concat(beads_results)
    end

    if has_regular_boards
      fizzy_results = Current.user.search(query).to_a
      results.concat(fizzy_results)
    end

    # Sort merged results by created_at desc
    results = results.sort_by { |r| r.created_at }.reverse

    # Wrap array in relation-like object for geared_pagination
    array_relation = ArrayRelation.new(results)
    set_page_and_extract_portion_from array_relation

    @recent_search_queries = Current.user.search_queries.order(updated_at: :desc).limit(10)
  end
end
