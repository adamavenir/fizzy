class BeadsBridge
  class Error < StandardError; end

  attr_reader :board

  def initialize(board)
    @board = board
  end

  def poll_and_broadcast
    return unless board.beads_enabled?

    mutations = fetch_mutations

    # Only broadcast if there are actual mutations
    if mutations.any?
      Rails.logger.info("BeadsBridge: Processing #{mutations.size} mutations for board #{board.id}")
      process_mutations(mutations)
      update_timestamp(mutations.last["Timestamp"])
    end
  rescue BeadsClient::Error => e
    Rails.logger.error("BeadsBridge poll error for board #{board.id}: #{e.message}")
    raise Error, e.message
  end

  private
    def fetch_mutations
      client = board.beads_client
      client.get_mutations(since: board.last_mutation_timestamp)
    end

    def process_mutations(mutations)
      return if mutations.empty?

      refresh_columns
    end

    def refresh_columns
      board.columns.sorted.each do |column|
        Turbo::StreamsChannel.broadcast_refresh_to(
          board,
          target: ActionView::RecordIdentifier.dom_id(column, :cards)
        )
      end
    end

    def update_timestamp(timestamp)
      return unless timestamp

      # Convert ISO8601 timestamp to milliseconds since epoch
      timestamp_ms = (Time.parse(timestamp).to_f * 1000).to_i

      board.update_column(:last_mutation_timestamp, timestamp_ms)
      Rails.logger.info("BeadsBridge: Updated timestamp to #{timestamp_ms} (#{timestamp})")
    end
end
