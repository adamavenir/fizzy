class BeadsMutationPollerJob < ApplicationJob
  queue_as :default

  def perform(board_id)
    board = Board.find_by(id: board_id)
    return unless board&.beads_enabled?

    bridge = BeadsBridge.new(board)
    bridge.poll_and_broadcast

    self.class.set(wait: 5.seconds).perform_later(board_id)
  rescue => e
    Rails.logger.error("BeadsMutationPollerJob failed for board #{board_id}: #{e.message}")
    raise
  end
end
