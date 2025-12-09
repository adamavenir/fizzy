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
  before_validation :normalize_repo_path, if: -> { repo_path.present? }
  after_create :initialize_beads_timestamp, if: -> { beads_enabled? }
  after_create :ensure_beads_prefix, if: -> { beads_enabled? }

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

  # Creates execution columns for beads integration.
  # Fizzy's built-in columns handle triage (Maybe?, Not Now) and closed.
  # These columns show beads issues by status.
  def create_default_beads_columns
    colors = Color::COLORS.map(&:value)
    [
      { name: "Open",        position: 0, column_type: :beads_status, beads_value: "open",        color: colors[0] },  # Blue
      { name: "In Progress", position: 1, column_type: :beads_status, beads_value: "in_progress", color: colors[3] },  # Yellow
      { name: "Blocked",     position: 2, column_type: :beads_status, beads_value: "blocked",     color: colors[8] }   # Pink
    ].each { |attrs| columns.create!(attrs) }
  end

  def ensure_beads_prefix
    return beads_prefix if beads_prefix.present?

    prefix = fetch_beads_prefix
    update_column(:beads_prefix, prefix) if prefix
    prefix
  end

  private
    def normalize_repo_path
      path = repo_path.strip

      # If user entered /path/to/.beads, trim the .beads part
      if path.end_with?("/.beads")
        self.repo_path = path.chomp("/.beads")
        return
      end

      # If path contains .beads but doesn't end with it (e.g., /path/.beads/something)
      if path.include?("/.beads/") || path.include?("/.beads")
        # Extract everything before .beads
        self.repo_path = path.split("/.beads").first
        return
      end

      # If path is a directory containing .beads, use it as-is
      # If path is a directory that itself contains a dir with .beads, that's fine too
    end

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

    def initialize_beads_timestamp
      # Start from current time to skip historical mutations
      current_ms = (Time.now.to_f * 1000).to_i
      update_column(:last_mutation_timestamp, current_ms)
    end

    def fetch_beads_prefix
      return nil unless repo_path.present?

      db_path = File.join(repo_path, ".beads", "beads.db")
      return nil unless File.exist?(db_path)

      result = `sqlite3 "#{db_path}" "SELECT value FROM config WHERE key='issue_prefix' LIMIT 1" 2>/dev/null`.strip
      result.presence
    end
end
