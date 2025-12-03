# Value object wrapping a Beads comment.
# Provides a Comment-like interface for Fizzy views.
class BeadsComment
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :id, :string
  attribute :text, :string
  attribute :author, :string
  attribute :created_at, :datetime

  attr_accessor :card, :board

  KNOWN_ATTRIBUTES = %i[id text author created_at].freeze

  def initialize(attributes = {})
    return super({}) unless attributes.is_a?(Hash)

    attrs = attributes.deep_symbolize_keys

    # Filter to known attributes (ignore route params like issue_id, board_id, etc)
    attrs = attrs.slice(*KNOWN_ATTRIBUTES)

    # Parse datetime
    if attrs[:created_at].is_a?(String)
      attrs[:created_at] = Time.parse(attrs[:created_at]) rescue nil
    end

    # Map 'text' to 'body' for consistency
    attrs[:text] = attrs[:body] if attrs[:body].present?

    super(attrs)
  end

  def body
    text
  end

  def creator
    return @creator_user if @creator_user

    # Try to find user by email
    if author.present? && board.respond_to?(:account) && board.account
      identity = Identity.find_by(email_address: author)
      user = identity&.users&.find_by(account: board.account) if identity
      @creator_user = user if user
    end

    @creator_user ||= OpenStruct.new(
      name: author || "Unknown",
      familiar_name: author || "Unknown",
      to_param: (author || "unknown").parameterize,
      system?: false,
      account: board.respond_to?(:account) ? board.account : OpenStruct.new(slug: "")
    )
  end

  def creator_id
    creator.respond_to?(:id) ? creator.id : nil
  end

  def dom_id
    "beads_comment_#{id}"
  end

  def to_key
    [id]
  end

  def to_param
    id
  end

  def persisted?
    id.present?
  end
end
