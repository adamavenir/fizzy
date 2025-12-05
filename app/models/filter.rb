class Filter < ApplicationRecord
  include Fields, Params, Resources, Summarized

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  class << self
    def from_params(params)
      find_by_params(params) || build(params)
    end

    def remember(attrs)
      create!(attrs)
    rescue ActiveRecord::RecordNotUnique
      find_by_params(attrs).tap(&:touch)
    end
  end

  def cards
    @cards ||= begin
      # If filtering beads boards with tags, fetch from beads API
      if filtering_beads_boards_with_tags?
        beads_cards
      else
        result = creator.accessible_cards.preloaded.published
        result = result.indexed_by(indexed_by)
        result = result.sorted_by(sorted_by)
        result = result.where(id: card_ids) if card_ids.present?
        result = result.where.missing(:not_now) unless include_not_now_cards?
        result = result.open unless include_closed_cards?
        result = result.unassigned if assignment_status.unassigned?
        result = result.assigned_to(assignees.ids) if assignees.present?
        result = result.where(creator_id: creators.ids) if creators.present?
        result = result.where(board: boards.ids) if boards.present?
        result = result.tagged_with(tags.ids) if tags.present?
        result = result.where("cards.created_at": creation_window) if creation_window
        result = result.closed_at_window(closure_window) if closure_window
        result = result.closed_by(closers) if closers.present?
        result = terms.reduce(result) do |result, term|
          result.mentioning(term, user: creator)
        end

        result.distinct
      end
    end
  end

  def empty?
    self.class.normalize_params(as_params).blank?
  end

  def single_board
    boards.first if boards.one?
  end

  def single_workflow
    boards.first.workflow if boards.pluck(:workflow_id).uniq.one?
  end

  def cacheable?
    boards.exists?
  end

  def cache_key
    ActiveSupport::Cache.expand_cache_key params_digest, "filter"
  end

  def only_closed?
    indexed_by.closed? || closure_window || closers.present?
  end

  private
    def filtering_beads_boards_with_tags?
      return false unless tags.present?
      target_boards = boards.present? ? boards : creator.boards
      target_boards.any?(&:beads_enabled?)
    end

    def beads_cards
      # Separate tags into categories for beads API
      # Priority tags (p0-p4) map to beads priority field, not labels
      # Type tags (bug, feature, epic, chore) map to beads issue_type field
      tag_titles = tags.map(&:title)

      priority_tags = tag_titles.select { |t| t.match?(/^p[0-4]$/) }
      type_tags = tag_titles & %w[bug feature epic chore]
      label_filters = tag_titles - priority_tags - type_tags

      # Build filter params
      filter_params = {}
      filter_params[:labels] = label_filters if label_filters.present?
      filter_params[:priority] = priority_tags.first.sub("p", "").to_i if priority_tags.one?
      filter_params[:issue_type] = type_tags.first if type_tags.one?

      # If no boards selected, search all user's beads boards
      target_boards = boards.present? ? boards : creator.boards

      # Fetch issues from all beads boards with filtering
      all_issues = target_boards.flat_map do |board|
        next [] unless board.beads_enabled?
        client = board.beads_client
        next [] unless client

        begin
          issues = filter_params.present? ? client.list(**filter_params) : client.list
          issues.map do |data|
            issue = BeadsIssue.new(data)
            issue.board = board
            issue
          end
        rescue BeadsClient::DaemonNotRunningError => e
          Rails.logger.warn("Filter: Daemon not running for board #{board.id}")
          []
        end
      end

      # Post-filter for multiple priorities or types (beads API only supports single values)
      if priority_tags.many?
        priorities = priority_tags.map { |t| t.sub("p", "").to_i }
        all_issues = all_issues.select { |i| priorities.include?(i.priority) }
      end
      if type_tags.many?
        all_issues = all_issues.select { |i| type_tags.include?(i.issue_type) }
      end

      # Sort by priority and created_at
      all_issues.sort_by { |i| [i.priority || 2, i.created_at || Time.at(0)] }
    end

    def include_closed_cards?
      only_closed? || card_ids.present?
    end

    def include_not_now_cards?
      indexed_by.not_now? || card_ids.present?
    end
end
