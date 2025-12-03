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
    ActiveModel::Name.new(self.class, nil, "BeadsIssue")
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
    labels&.reject { |l| l.start_with?("fizzy:") } || []
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

  def active?
    !closed? && !postponed?
  end

  def published?
    true  # Beads issues are always "published"
  end

  def drafted?
    false
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

  # Association stubs for view compatibility
  def column
    nil
  end

  def creator
    OpenStruct.new(
      name: assignee || "Beads",
      familiar_name: assignee || "Beads"
    )
  end

  def board
    @board ||= OpenStruct.new(name: "")
  end

  def board=(b)
    @board = b
  end

  def assignees
    assignee.present? ? [OpenStruct.new(name: assignee, familiar_name: assignee)] : []
  end

  def tags
    non_fizzy_labels.map { |l| OpenStruct.new(title: l) }
  end

  def image
    OpenStruct.new(attached?: false)
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
