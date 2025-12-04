class Beads::Issues::TaggingsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def new
    @card = @issue

    # Ensure built-in beads tags exist in Fizzy
    ensure_beads_tags_exist

    # Get tag titles currently on this beads issue
    current_tag_titles = @card.tags.map(&:title)

    # Get all account tags
    all_tags = Current.account.tags.alphabetically

    # Separate into tagged and untagged based on title match
    @tagged_with = all_tags.select { |t| current_tag_titles.include?(t.title) }
    @tags = all_tags.reject { |t| current_tag_titles.include?(t.title) }

    fresh_when etag: [ @tags, @card.tags ]
  end

  def create
    client = @board.beads_client
    tag_title = sanitized_tag_title_param

    # Check if this is a special tag (priority or type)
    if tag_title.match?(/^p[0-4]$/i)
      # Priority tag: p0, p1, p2, p3, p4
      current_priority_tag = "p#{@issue.priority}"

      if tag_title == current_priority_tag
        # Clicking current priority - reset to default (p2)
        client.update(@issue.id, priority: 2)
      else
        # Change to new priority
        priority = tag_title[1].to_i
        client.update(@issue.id, priority: priority)
      end
    elsif %w[bug feature epic chore].include?(tag_title.downcase)
      # Type tags (skip task - it's immutable)
      has_type_in_labels = @issue.labels.include?(tag_title.downcase)

      if has_type_in_labels
        # Remove this type label
        client.remove_label(@issue.id, tag_title.downcase)
      else
        # Remove old type labels
        @issue.labels.select { |l| %w[bug feature epic chore].include?(l) }.each do |old_type|
          client.remove_label(@issue.id, old_type)
        end
        # Add new type as label
        client.add_label(@issue.id, tag_title.downcase)
      end
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

      # Type tags: bug, feature, epic, chore (skip task - it's the default and can't be changed)
      %w[bug feature epic chore].each do |tag_title|
        Current.account.tags.find_or_create_by!(title: tag_title)
      end
    end
end
