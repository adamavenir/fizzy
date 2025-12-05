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
      # Check if we're filtering beads-enabled boards
      if filtering_beads_boards?
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
    def filtering_beads_boards?
      target_boards = boards.present? ? boards : creator.boards
      target_boards.any?(&:beads_enabled?)
    end

    def beads_cards
      # Separate tags into categories for beads API
      # Priority tags (p0-p4) map to beads priority field, not labels
      # Type tags (bug, feature, epic, chore) map to beads issue_type field
      tag_titles = tags.map(&:title)

      priority_tags = tag_titles.select { |t| t.match?(/^p[0-4]$/) }
      # Note: beads issue_types are: bug, epic, chore, task (default)
      # "feature" is a regular label, not an issue_type
      type_tags = tag_titles & %w[bug epic chore task]
      label_filters = tag_titles - priority_tags - type_tags

      # Build filter params for beads API
      filter_params = {}
      filter_params[:labels] = label_filters if label_filters.present?
      filter_params[:priority] = priority_tags.first.sub("p", "").to_i if priority_tags.one?
      filter_params[:issue_type] = type_tags.first if type_tags.one?

      # Status filter (indexed_by maps to beads status)
      filter_params[:status] = beads_status_for_indexed_by

      # Assignee filter - beads uses email addresses
      if assignees.present?
        # Get emails for selected assignees via their identities
        assignee_emails = assignees.flat_map { |u| u.identity&.email_address }.compact
        filter_params[:assignee] = assignee_emails.first if assignee_emails.one?
      end

      # If no boards selected, search all user's beads boards
      target_boards = boards.present? ? boards : creator.boards

      # Fetch issues from all beads boards with filtering
      all_issues = target_boards.flat_map do |board|
        next [] unless board.beads_enabled?
        client = board.beads_client
        next [] unless client

        begin
          issues = filter_params.compact.present? ? client.list(**filter_params.compact) : client.list
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

      # Post-filter for multiple assignees (beads API only supports single value)
      if assignees.many?
        assignee_emails = assignees.flat_map { |u| u.identity&.email_address }.compact
        all_issues = all_issues.select { |i| assignee_emails.include?(i.assignee) }
      end

      # Post-filter for unassigned
      if assignment_status.unassigned?
        all_issues = all_issues.select { |i| i.assignee.blank? }
      end

      # Post-filter for creators (beads tracks creator via creator: label)
      # Issues without a creator: label are considered created by Beads (hi@fizzybeads.com)
      if creators.present?
        creator_emails = creators.flat_map { |u| u.identity&.email_address }.compact
        beads_selected = creator_emails.include?("hi@fizzybeads.com")

        all_issues = all_issues.select do |i|
          if i.creator_email.nil?
            # Issues without creator: label match "Beads" user
            beads_selected
          else
            creator_emails.include?(i.creator_email)
          end
        end
      end

      # Post-filter for indexed_by special cases
      case indexed_by.to_s
      when "not_now"
        # Filter for issues with fizzy:not-now label
        all_issues = all_issues.select { |i| i.labels&.include?("fizzy:not-now") }
      when "golden"
        # Golden = P0 priority issues
        all_issues = all_issues.select { |i| i.priority == 0 }
      when "stalled"
        # Stalled = open issues with no activity for 2+ weeks
        two_weeks_ago = 2.weeks.ago
        all_issues = all_issues.select do |i|
          i.status == "open" && (i.updated_at || i.created_at) < two_weeks_ago
        end
      end

      # Apply sorting
      all_issues = sort_beads_issues(all_issues)

      all_issues
    end

    def beads_status_for_indexed_by
      case indexed_by.to_s
      when "closed"
        "closed"
      when "all"
        "open"  # Default to open status (includes in_progress, blocked)
      when "not_now"
        nil  # Will post-filter for fizzy:not-now label
      when "golden"
        nil  # Will post-filter for P0 issues
      when "in_progress"
        "in_progress"
      when "blocked"
        "blocked"
      else
        nil  # Let beads return all, filter in Ruby
      end
    end

    def sort_beads_issues(issues)
      case sorted_by.to_s
      when "newest"
        issues.sort_by { |i| i.created_at || Time.at(0) }.reverse
      when "oldest"
        issues.sort_by { |i| i.created_at || Time.at(0) }
      when "latest"
        # Latest activity - use updated_at
        issues.sort_by { |i| i.updated_at || i.created_at || Time.at(0) }.reverse
      else
        # Default: sort by priority then created_at
        issues.sort_by { |i| [i.priority || 2, i.created_at || Time.at(0)] }
      end
    end

    def include_closed_cards?
      only_closed? || card_ids.present?
    end

    def include_not_now_cards?
      indexed_by.not_now? || card_ids.present?
    end
end
