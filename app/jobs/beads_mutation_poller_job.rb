class BeadsMutationPollerJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(board_id) { "beads_poll_#{board_id}" }

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
