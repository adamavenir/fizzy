namespace :beads do
  desc "Remove duplicate events from activity feed"
  task fix_duplicates: :environment do
    puts "Finding duplicate beads events..."

    # Group events by board, action, issue, and second
    duplicates_by_key = Event.where("action LIKE ?", "beads_%")
         .where("particulars->>'beads_issue_id' IS NOT NULL")
         .order(created_at: :asc)
         .group_by { |e| [e.board_id, e.action, e.beads_issue_id, e.created_at.to_i] }
         .select { |_, events| events.count > 1 }

    total_deleted = 0

    duplicates_by_key.each do |key, events|
      board_id, action, issue_id, timestamp = key

      # Keep the first event, delete the rest
      keep = events.first
      duplicates = events[1..-1]

      puts "\n#{action} for #{issue_id} (#{events.count} events at #{Time.at(timestamp)})"
      puts "  Keeping: #{keep.id}"
      puts "  Deleting: #{duplicates.map(&:id).join(', ')}"

      duplicates.each do |event|
        event.destroy
        total_deleted += 1
      end
    end

    puts "\n" + "="*60
    puts "Total duplicate events deleted: #{total_deleted}"
  end
end
