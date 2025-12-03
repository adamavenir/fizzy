class Board < ApplicationRecord
  include Accessible, AutoPostponing, Broadcastable, Cards, Entropic, Filterable, Publishable, Triageable

  belongs_to :creator, class_name: "User", default: -> { Current.user }
  belongs_to :account, default: -> { creator.account }

  has_rich_text :public_description

  has_many :tags, -> { distinct }, through: :cards
  has_many :events
  has_many :webhooks, dependent: :destroy

  scope :alphabetically, -> { order("lower(name)") }
  scope :ordered_by_recently_accessed, -> { merge(Access.ordered_by_recently_accessed) }

  validate :repo_has_beads_directory, if: -> { repo_path.present? }

  def beads_client
    return nil unless repo_path.present?
    @beads_client ||= BeadsClient.new(repo_path)
  end

  def beads_enabled?
    repo_path.present? && File.exist?(File.join(repo_path, ".beads"))
  end

  def cards_for_column(column)
    return column.cards unless beads_enabled?
    BeadsCardQuery.new(self).for_column(column)
  end

  # Creates default columns for the hybrid fizzy/beads model
  def create_default_beads_columns
    colors = Color::COLORS.map(&:value)
    [
      { name: "Maybe",       position: 0, column_type: :fizzy_tag,    beads_value: "fizzy:maybe",   color: colors[2] },  # Tan
      { name: "Not Now",     position: 1, column_type: :fizzy_tag,    beads_value: "fizzy:not-now", color: colors[1] },  # Gray
      { name: "Open",        position: 2, column_type: :beads_status, beads_value: "open",          color: colors[0] },  # Blue
      { name: "In Progress", position: 3, column_type: :beads_status, beads_value: "in_progress",   color: colors[3] },  # Yellow
      { name: "Blocked",     position: 4, column_type: :beads_status, beads_value: "blocked",       color: colors[8] },  # Pink
      { name: "Done",        position: 5, column_type: :beads_status, beads_value: "closed",        color: colors[4] }   # Lime
    ].each { |attrs| columns.create!(attrs) }
  end

  private
    def repo_has_beads_directory
      return if repo_path.blank?

      unless File.directory?(repo_path)
        errors.add(:repo_path, "directory does not exist")
        return
      end

      unless File.exist?(File.join(repo_path, ".beads"))
        errors.add(:repo_path, "does not contain a .beads directory")
      end
    end
end
