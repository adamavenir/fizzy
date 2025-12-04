require "ostruct"

# Value object wrapping a Beads issue JSON response.
# Provides a Card-like interface for views.
#
# Usage:
#   data = beads_client.show("bd-abc123")
#   issue = BeadsIssue.new(data)
#   issue.title          # => "Fix the bug"
#   issue.closed?        # => false
#   issue.dom_id         # => "beads_issue_bd_abc123"
#
class BeadsIssue
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Serializers::JSON

  attribute :id, :string
  attribute :title, :string
  attribute :description, :string
  attribute :status, :string
  attribute :priority, :integer, default: 2
  attribute :issue_type, :string, default: "task"
  attribute :assignee, :string
  attribute :labels, default: -> { [] }
  attribute :created_at, :datetime
  attribute :updated_at, :datetime
  attribute :closed_at, :datetime
  attribute :comments, default: -> { [] }
  attribute :dependencies, default: -> { [] }
  attribute :design, :string
  attribute :acceptance_criteria, :string
  attribute :notes, :string
  attribute :external_ref, :string
  attribute :dependency_count, :integer, default: 0
  attribute :blocked_by, default: -> { [] }
  attribute :blocks, default: -> { [] }

  KNOWN_ATTRIBUTES = %i[
    id title description status priority issue_type assignee labels
    created_at updated_at closed_at comments dependencies design
    acceptance_criteria notes external_ref dependency_count blocked_by blocks
  ].freeze

  def initialize(attributes = {})
    # Handle both symbol and string keys
    attrs = attributes.is_a?(Hash) ? attributes.deep_symbolize_keys : {}

    # Filter to known attributes only (beads may return extra fields)
    attrs = attrs.slice(*KNOWN_ATTRIBUTES)

    # Parse datetime strings
    %i[created_at updated_at closed_at].each do |field|
      if attrs[field].is_a?(String)
        attrs[field] = Time.parse(attrs[field]) rescue nil
      end
    end

    super(attrs)
  end

  # Short ID for display (just the hash part)
  def short_id
    return "" if id.blank?
    id.split("-").last&.upcase || id
  end

  # Fizzy compatibility: fake number for display
  def number
    short_id
  end

  def closed?
    status == "closed"
  end

  def open?
    status == "open"
  end

  def in_progress?
    status == "in_progress"
  end

  def blocked?
    status == "blocked"
  end

  # Virtual column_id - determined by status/labels, not stored
  def column_id
    nil
  end

  # DOM ID for Turbo Stream targeting
  def dom_id
    "beads_issue_#{id.to_s.tr('-', '_')}"
  end

  # For ActionView helpers
  def to_key
    [id]
  end

  def to_param
    id
  end

  def persisted?
    id.present?
  end

  def model_name
    @model_name ||= ActiveModel::Name.new(self.class, nil, "Issue")
  end

  # For polymorphic_path to work with form_with
  def to_model
    self
  end

  # Priority display helpers
  def priority_name
    case priority
    when 0 then "Critical"
    when 1 then "High"
    when 2 then "Medium"
    when 3 then "Low"
    when 4 then "None"
    else "Medium"
    end
  end

  def priority_color
    case priority
    when 0 then "red"
    when 1 then "orange"
    when 2 then "yellow"
    when 3 then "blue"
    when 4 then "gray"
    else "yellow"
    end
  end

  # CSS variable for card color based on priority
  def color
    case priority
    when 0 then "var(--color-card-8)"  # Pink for critical
    when 1 then "var(--color-card-3)"  # Yellow for high
    when 2 then "var(--color-card-default)"  # Blue for medium
    when 3 then "var(--color-card-5)"  # Aqua for low
    when 4 then "var(--color-card-1)"  # Gray for none
    else "var(--color-card-default)"
    end
  end

  # Label helpers
  def has_label?(label)
    labels&.include?(label)
  end

  def fizzy_labels
    labels&.select { |l| l.start_with?("fizzy:") } || []
  end

  def non_fizzy_labels
    labels&.reject { |l| l.start_with?("fizzy:") || l.start_with?("creator:") } || []
  end

  def in_triage?
    fizzy_labels.any?
  end

  # Fizzy Card compatibility methods
  def golden?
    priority == 0  # Critical issues get the golden effect
  end

  def postponed?
    has_label?("fizzy:not-now")
  end

  def postponed_at
    updated_at if postponed?
  end

  def postponed_by
    nil  # Beads doesn't track who postponed
  end

  def closed_by
    creator  # Assume same creator closed it
  end

  def active?
    !closed? && !postponed?
  end

  def published?
    true  # Beads issues are always "published"
  end

  def drafted?
    status == "draft"
  end

  def triaged?
    !in_triage?  # Triaged = not in triage columns
  end

  def entropic?
    false  # No entropy tracking for beads issues
  end

  def has_attachments?
    false  # Beads doesn't track attachments
  end

  def last_active_at
    updated_at || created_at
  end

  def steps
    []  # Beads doesn't have steps/checklists
  end

  def comments
    return @comments_collection if @comments_collection

    # Fetch comments from beads and wrap in BeadsComment objects
    return [] unless board.respond_to?(:beads_client)

    comment_data = board.beads_client.list_comments(id)
    @comments_collection = CommentCollection.new(
      comment_data.map do |data|
        comment = BeadsComment.new(data)
        comment.card = self
        comment.board = board
        comment
      end
    )
  end

  # Collection wrapper to provide ActiveRecord-like interface
  class CommentCollection < Array
    def preloaded
      self
    end

    def chronologically
      sort_by { |c| c.created_at || Time.at(0) }
    end
  end

  # Image handling via markdown cover convention
  # Images stored in .beads/images/ and referenced as ![cover](images/filename.png)
  def cover_image_path
    return nil if description.blank?

    first_line = description.lines.first&.strip
    return nil unless first_line

    # Match ![cover](path) or ![cover](url)
    match = first_line.match(/^\!\[cover\]\((.+?)\)/)
    match ? match[1] : nil
  end

  def description_without_cover
    return description if cover_image_path.nil?
    description.lines[1..-1]&.join || ""
  end

  def cover_image_url
    path = cover_image_path
    return nil unless path

    # If it's a full URL, return as-is
    return path if path.start_with?("http://", "https://")

    # Otherwise, use Rails route helper
    Rails.application.routes.url_helpers.beads_image_path(
      board_id: board.id,
      path: path.sub(/^images\//, "")
    )
  end

  # Association stubs for view compatibility
  def column
    nil
  end

  def creator
    return @creator if @creator

    # First, try to find creator from the creator: label
    creator_label = labels&.find { |l| l.start_with?("creator:") }
    if creator_label && board.respond_to?(:account) && board.account
      creator_email = creator_label.sub("creator:", "")
      identity = Identity.find_by(email_address: creator_email)
      if identity
        @creator = identity.users.find_by(account: board.account)
        return @creator if @creator
      end
    end

    # Fallback to built-in Beads user (hi@fizzybeads.com)
    if board.respond_to?(:account) && board.account
      beads_identity = Identity.find_by(email_address: "hi@fizzybeads.com")
      if beads_identity
        @creator = beads_identity.users.find_by(account: board.account)
        return @creator if @creator
      end
    end

    # Fallback to fake user if Beads user doesn't exist
    account = board.respond_to?(:account) && board.account ? board.account : OpenStruct.new(slug: "")
    @creator = OpenStruct.new(
      name: "Beads",
      familiar_name: "Beads",
      to_param: "beads",
      account: account
    )
  end

  def board
    @board ||= OpenStruct.new(name: "")
  end

  def board=(b)
    @board = b
  end

  def assignees
    return [] if assignee.blank?

    # Try to find a User in the current account via Identity email lookup
    user = assignee_user
    if user
      [user]
    else
      # Create a fake user object for display
      [OpenStruct.new(
        name: assignee,
        familiar_name: assignee,
        to_param: assignee.parameterize,
        id: nil
      )]
    end
  end

  def assignee_user
    return nil if assignee.blank?
    return nil unless board.respond_to?(:account) && board.account

    identity = Identity.find_by(email_address: assignee)
    return nil unless identity

    identity.users.find_by(account: board.account)
  end

  def tags
    all_labels = []

    # Add priority tag
    all_labels << "p#{priority}" if priority.present?

    # Add type tag (skip default 'task')
    all_labels << issue_type if issue_type.present? && issue_type != "task"

    # Add regular labels
    all_labels += non_fizzy_labels

    all_labels.map { |l| OpenStruct.new(title: l, id: nil) }
  end

  def tagged_with?(tag)
    tags.any? { |t| t.title == tag.title }
  end

  def image
    if cover_image_path.present?
      OpenStruct.new(
        attached?: true,
        url: cover_image_url,
        presence: cover_image_url
      )
    else
      OpenStruct.new(attached?: false, url: nil, presence: nil)
    end
  end

  # Type check
  def beads_issue?
    true
  end

  # Comparison for sorting
  def <=>(other)
    return nil unless other.is_a?(BeadsIssue)

    # Sort by priority (lower is higher priority), then by created_at (older first)
    result = (priority || 2) <=> (other.priority || 2)
    return result unless result == 0

    (created_at || Time.at(0)) <=> (other.created_at || Time.at(0))
  end
end
