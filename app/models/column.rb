class Column < ApplicationRecord
  include Colored, Positioned

  belongs_to :account, default: -> { board.account }
  belongs_to :board, touch: true
  has_many :cards, dependent: :nullify

  # Column types for hybrid model:
  # - fizzy_tag: Triage columns backed by fizzy: labels on open issues
  # - beads_status: Execution columns backed by beads status field
  enum :column_type, { fizzy_tag: 0, beads_status: 1 }

  after_save_commit    -> { cards.touch_all }, if: -> { saved_change_to_name? || saved_change_to_color? }
  after_destroy_commit -> { board.cards.touch_all }

  def fizzy_triage?
    fizzy_tag?
  end

  # Returns BeadsIssue objects for this column
  def beads_cards
    # Use cached cards if available (set by BoardsController for eager loading)
    return @beads_cards_cache if defined?(@beads_cards_cache)

    return [] unless board.repo_path.present?
    BeadsCardQuery.new(board).for_column(self)
  end
end
