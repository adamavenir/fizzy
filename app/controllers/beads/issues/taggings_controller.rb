class Beads::Issues::TaggingsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def new
    @card = @issue

    # Ensure built-in beads tags exist in Fizzy
    ensure_beads_tags_exist

    # BeadsIssue.tags returns an array of Tag objects, so we need to sort manually
    @tagged_with = @card.tags.sort_by(&:title)
    # Get all account tags not already on the card
    tagged_ids = @tagged_with.map(&:id)
    @tags = Current.account.tags.alphabetically.where.not(id: tagged_ids)
    fresh_when etag: [ @tags, @card.tags ]
  end

  def create
    client = @board.beads_client
    tag_title = sanitized_tag_title_param

    # Check if this is a special tag (priority or type)
    if tag_title.match?(/^p[0-4]$/i)
      # Priority tag: p0, p1, p2, p3, p4
      priority = tag_title[1].to_i
      client.update(@issue.id, priority: priority)
    elsif %w[bug feature epic chore task].include?(tag_title.downcase)
      # Type tag
      client.update(@issue.id, issue_type: tag_title.downcase)
    else
      # Regular label - check if we're toggling it
      if @issue.labels.include?(tag_title)
        client.remove_label(@issue.id, tag_title)
      else
        client.add_label(@issue.id, tag_title)
      end
    end

    # Reload issue
    data = client.show(@issue.id)
    @issue = BeadsIssue.new(data)
    @issue.board = @board
    @card = @issue
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def set_issue
      return unless @board&.beads_enabled?
      data = @board.beads_client.show(params[:issue_issue_id])
      @issue = BeadsIssue.new(data)
      @issue.board = @board
    end

    def sanitized_tag_title_param
      params.required(:tag_title).strip.gsub(/\A#/, "")
    end

    def ensure_beads_tags_exist
      # Priority tags: p0, p1, p2, p3, p4
      %w[p0 p1 p2 p3 p4].each do |tag_title|
        Current.account.tags.find_or_create_by!(title: tag_title)
      end

      # Type tags: bug, feature, epic, chore, task
      %w[bug feature epic chore task].each do |tag_title|
        Current.account.tags.find_or_create_by!(title: tag_title)
      end
    end
end
