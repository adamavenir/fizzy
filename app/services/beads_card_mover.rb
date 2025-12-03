# Handles moving BeadsIssue cards between columns in the hybrid model.
# Maps column transitions to the appropriate beads operations (status changes, label changes).
#
# Usage:
#   mover = BeadsCardMover.new(board.beads_client)
#   mover.move("bd-abc123", from_column, to_column)
#
class BeadsCardMover
  class MoveError < StandardError; end

  def initialize(client)
    @client = client
  end

  # Move a card from one column to another.
  # Handles all four transition types:
  # - fizzy_tag -> beads_status (promoting from triage)
  # - beads_status -> fizzy_tag (demoting back to triage)
  # - fizzy_tag -> fizzy_tag (moving between triage columns)
  # - beads_status -> beads_status (moving between execution columns)
  def move(card_id, from_column, to_column)
    return if from_column == to_column

    if from_column.fizzy_tag? && to_column.beads_status?
      promote_from_triage(card_id, from_column, to_column)
    elsif from_column.beads_status? && to_column.fizzy_tag?
      demote_to_triage(card_id, to_column)
    elsif from_column.fizzy_tag? && to_column.fizzy_tag?
      move_between_triage(card_id, from_column, to_column)
    else
      move_between_statuses(card_id, to_column)
    end
  end

  private
    # Promoting: remove fizzy tag, set status (if not "open")
    def promote_from_triage(card_id, from_column, to_column)
      @client.remove_label(card_id, from_column.beads_value)

      # Only update status if moving to non-open column
      # (Open column just means no fizzy: labels)
      if to_column.beads_value != "open"
        @client.update(card_id, status: to_column.beads_value)
      end
    end

    # Demoting back to triage: add fizzy tag, reset to open status
    def demote_to_triage(card_id, to_column)
      @client.add_label(card_id, to_column.beads_value)
      @client.update(card_id, status: "open")
    end

    # Moving between triage columns: swap fizzy tags
    def move_between_triage(card_id, from_column, to_column)
      @client.remove_label(card_id, from_column.beads_value)
      @client.add_label(card_id, to_column.beads_value)
    end

    # Moving between beads statuses: just update status
    def move_between_statuses(card_id, to_column)
      status = to_column.beads_value

      # Handle special case: "closed" column uses close operation
      if status == "closed"
        @client.close(card_id)
      else
        @client.update(card_id, status: status)
      end
    end
end
