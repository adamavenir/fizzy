namespace :beads do
  desc "Rebuild state cache for a board (usage: beads:rebuild_cache[board_id])"
  task :rebuild_cache, [:board_id] => :environment do |t, args|
    unless args[:board_id]
      puts "Usage: bin/rails beads:rebuild_cache[board_id]"
      exit 1
    end

    board = Board.find(args[:board_id])
    puts "Rebuilding cache for board: #{board.name}"

    # Clear existing cache
    deleted = BeadsIssueState.where(board: board).delete_all
    puts "  Deleted #{deleted} cached entries"

    # Fetch all issues from beads across all statuses
    client = board.beads_client
    all_issues = []

    %w[open in_progress blocked closed].each do |status|
      begin
        issues = client.list(status: status) || []
        all_issues.concat(issues)
        puts "  Found #{issues.size} #{status} issues"
      rescue => e
        puts "  Warning: Could not fetch #{status} issues: #{e.message}"
      end
    end

    puts "  Total issues found: #{all_issues.size}"

    # Populate cache
    all_issues.each do |issue_data|
      issue = BeadsIssue.new(issue_data)
      issue.board = board

      # Serialize issue using same logic as BeadsBridge
      serialized = {
        id: issue.id,
        title: issue.title,
        description: issue.description,
        status: issue.status,
        priority: issue.priority,
        issue_type: issue.issue_type,
        assignee: issue.assignee,
        labels: issue.labels,
        comments: issue.comments.map { |c|
          { author: c.author, body: c.body, created_at: c.created_at&.iso8601 }
        },
        created_at: issue.created_at&.iso8601,
        updated_at: issue.updated_at&.iso8601,
        closed_at: issue.closed_at&.iso8601
      }

      BeadsIssueState.create!(
        board: board,
        issue_id: issue.id,
        snapshot: serialized.to_json,
        synced_at: Time.current
      )
    end

    puts "  ✓ Rebuilt cache with #{all_issues.size} issues"

  rescue ActiveRecord::RecordNotFound
    puts "Error: Board not found with id #{args[:board_id]}"
    exit 1
  rescue BeadsClient::Error => e
    puts "Error: Cannot connect to beads daemon: #{e.message}"
    puts "  Hint: Make sure the beads daemon is running for this board's repo"
    exit 1
  end

  desc "Check cache health for all beads-enabled boards"
  task check_cache: :environment do
    boards = Board.where.not(repo_path: nil)

    if boards.empty?
      puts "No beads-enabled boards found"
      exit 0
    end

    puts "Checking cache health for #{boards.count} board(s):\n\n"
    puts "#{"Board Name".ljust(30)} Cached / Actual"
    puts "-" * 50

    boards.each do |board|
      begin
        cached_count = BeadsIssueState.where(board: board).count

        # Try to get issue count from beads
        client = board.beads_client

        # Count issues across all statuses
        actual_count = 0
        %w[open in_progress blocked closed].each do |status|
          issues = client.list(status: status) || []
          actual_count += issues.size
        end

        status_icon = cached_count == actual_count ? "✓" : "⚠"
        puts "#{status_icon} #{board.name.ljust(30)} #{cached_count.to_s.rjust(3)} / #{actual_count.to_s.rjust(3)}"

      rescue BeadsClient::Error => e
        puts "✗ #{board.name.ljust(30)} Error: #{e.message}"
      end
    end

    puts ""
  end

  desc "Clean up orphaned cache entries (boards that no longer exist)"
  task clean_cache: :environment do
    puts "Cleaning orphaned cache entries..."

    # Find cache entries for deleted boards
    orphaned_count = 0

    BeadsIssueState.find_each do |state|
      unless Board.exists?(state.board_id)
        state.destroy
        orphaned_count += 1
      end
    end

    if orphaned_count > 0
      puts "✓ Deleted #{orphaned_count} orphaned cache entries"
    else
      puts "✓ No orphaned entries found"
    end
  end

  desc "Backfill state cache for all existing beads issues across all boards"
  task backfill_cache: :environment do
    puts "Starting state cache backfill for all beads boards...\n\n"

    boards = Board.where.not(repo_path: nil)

    if boards.empty?
      puts "No beads-enabled boards found"
      exit 0
    end

    total_cached = 0
    total_boards = 0
    failed_boards = []

    boards.find_each do |board|
      print "Backfilling cache for board: #{board.name}... "

      begin
        # Fetch all current issues across all statuses
        client = board.beads_client
        all_issues = []

        %w[open in_progress blocked closed].each do |status|
          issues = client.list(status: status) || []
          all_issues.concat(issues)
        end

        # Cache each issue (use find_or_create_by for idempotency)
        all_issues.each do |issue_data|
          issue = BeadsIssue.new(issue_data)
          issue.board = board

          # Serialize issue state
          serialized = {
            id: issue.id,
            title: issue.title,
            description: issue.description,
            status: issue.status,
            priority: issue.priority,
            issue_type: issue.issue_type,
            assignee: issue.assignee,
            labels: issue.labels,
            comments: issue.comments.map { |c|
              { author: c.author, body: c.body, created_at: c.created_at&.iso8601 }
            },
            created_at: issue.created_at&.iso8601,
            updated_at: issue.updated_at&.iso8601,
            closed_at: issue.closed_at&.iso8601
          }

          # Use find_or_initialize_by for idempotency (same as BeadsBridge)
          state = BeadsIssueState.find_or_initialize_by(
            board_id: board.id,
            issue_id: issue.id
          )

          state.snapshot = serialized.to_json
          state.synced_at = Time.current
          state.save!
        end

        total_cached += all_issues.size
        total_boards += 1
        puts "✓ Cached #{all_issues.size} issues"

      rescue BeadsClient::Error => e
        puts "✗ Failed: #{e.message}"
        failed_boards << { board: board.name, error: e.message }
      rescue => e
        puts "✗ Unexpected error: #{e.message}"
        failed_boards << { board: board.name, error: e.message }
      end
    end

    puts "\n" + "="*60
    puts "Backfill complete!"
    puts "  Boards processed: #{total_boards}/#{boards.count}"
    puts "  Total issues cached: #{total_cached}"

    if failed_boards.any?
      puts "\n  ⚠ Failed boards:"
      failed_boards.each do |failure|
        puts "    - #{failure[:board]}: #{failure[:error]}"
      end
    end
    puts "="*60
  end
end
