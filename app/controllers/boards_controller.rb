require 'ostruct'

class BoardsController < ApplicationController
  include FilterScoped

  before_action :set_board, except: %i[ new create ]
  before_action :ensure_permission_to_admin_board, only: %i[ update ]

  def show
    start_beads_polling if @board.beads_enabled?

    if @filter.used?(ignore_boards: true)
      show_filtered_cards
    else
      show_columns
    end
  end

  def new
    @board = Board.new
  end

  def create
    @board = Board.new(board_params.with_defaults(all_access: true))

    if @board.save
      @board.create_default_beads_columns if @board.beads_enabled?
      redirect_to board_path(@board)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    selected_user_ids = @board.users.pluck :id
    @selected_users, @unselected_users = \
      @board.account.users.active.alphabetically.includes(:identity).partition { |user| selected_user_ids.include? user.id }
  end

  def update
    @board.update! board_params
    @board.accesses.revise granted: grantees, revoked: revokees if grantees_changed?

    if @board.accessible_to?(Current.user)
      redirect_to edit_board_path(@board), notice: "Saved"
    else
      redirect_to root_path, notice: "Saved (you were removed from the board)"
    end
  end

  def destroy
    @board.destroy
    redirect_to root_path
  end

  private
    def set_board
      @board = Current.user.boards.find params[:id]
    end

    def ensure_permission_to_admin_board
      unless Current.user.can_administer_board?(@board)
        head :forbidden
      end
    end

    def grantees_changed?
      params.key?(:user_ids)
    end

    def show_filtered_cards
      @filter.board_ids = [ @board.id ]
      cards = @filter.cards
      if cards.is_a?(Array)
        # Wrap array in relation-like object for geared_pagination
        array_relation = ArrayRelation.new(cards)
        set_page_and_extract_portion_from array_relation
      else
        set_page_and_extract_portion_from cards
      end
    end

    def show_columns
      if @board.beads_enabled?
        begin
          # Test connection first to trigger auto-start or get meaningful error
          @board.beads_client.ping

          # Eager load all columns to avoid N+1 HTTP requests from lazy Turbo Frames
          query = BeadsCardQuery.new(@board)

          # Show beads issues with fizzy:maybe label (triage inbox)
          issues = @board.beads_client.list(status: "open", labels: ["fizzy:maybe"])
          @beads_cards = issues.map do |data|
            issue = BeadsIssue.new(data)
            issue.board = @board
            issue
          end
          @page = OpenStruct.new(records: @beads_cards, used?: @beads_cards.any?)

          # Pre-load all column cards to avoid lazy-loading HTTP overhead
          @board.columns.sorted.each do |column|
            column.instance_variable_set(:@beads_cards_cache, query.for_column(column))
          end

          # Pre-load Not Now and Closed columns as well
          not_now_stub = OpenStruct.new(
            column_type: "fizzy_tag",
            beads_value: "fizzy:not-now"
          )
          @not_now_cards = query.for_column(not_now_stub)

          closed_stub = OpenStruct.new(
            column_type: "fizzy_tag",
            beads_value: "closed"
          )
          # For closed, we need to fetch closed status issues
          closed_issues = @board.beads_client.list(status: "closed")
          @closed_cards = closed_issues.map do |data|
            issue = BeadsIssue.new(data)
            issue.board = @board
            issue
          end.sort_by { |i| i.closed_at || Time.at(0) }.reverse
        rescue BeadsClient::Error => e
          @beads_error = e.message
          flash.now[:alert] = e.message
          @page = OpenStruct.new(records: [], used?: false)
        end
      else
        cards = @board.cards.awaiting_triage.latest.with_golden_first.preloaded
        set_page_and_extract_portion_from cards
        fresh_when etag: [ @board, @page.records, @user_filtering ]
      end
    end

    def board_params
      params.expect(board: [ :name, :all_access, :auto_postpone_period, :public_description, :repo_path, :hide_child_cards ])
    end

    def grantees
      @board.account.users.active.where id: grantee_ids
    end

    def revokees
      @board.users.where.not id: grantee_ids
    end

    def grantee_ids
      params.fetch :user_ids, []
    end

    def start_beads_polling
      BeadsMutationPollerJob.perform_later(@board.id)
    end
end
