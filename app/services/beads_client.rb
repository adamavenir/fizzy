# Client for interacting with bd daemon via RPC over Unix socket.
#
# Usage:
#   client = BeadsClient.new("/path/to/repo")
#   client.ping              # => { "message" => "pong", "version" => "1.0.0" }
#   client.list(status: "open")
#   client.create(title: "New issue")
#
class BeadsClient
  class Error < StandardError; end
  class DaemonNotRunningError < Error; end
  class ConnectionError < Error; end

  SOCKET_TIMEOUT = 30
  DAEMON_START_TIMEOUT = 5

  attr_reader :repo_path

  def initialize(repo_path)
    @repo_path = File.expand_path(repo_path)
  end

  # Health check
  def ping
    rpc("ping", {})
  end

  def health
    rpc("health", {})
  end

  # Issue operations
  def list(status: nil, labels: nil, labels_any: nil, limit: nil, assignee: nil, priority: nil, issue_type: nil)
    args = { status:, labels:, labels_any:, limit:, assignee:, priority:, issue_type: }.compact
    rpc("list", args) || []
  end

  def search(query:, status: nil, labels: nil, labels_any: nil, limit: nil, assignee: nil, priority: nil, issue_type: nil)
    args = { query:, status:, labels:, labels_any:, limit:, assignee:, priority:, issue_type: }.compact
    rpc("list", args) || []
  end

  def show(id)
    rpc("show", { id: })
  end

  def create(title:, description: nil, labels: [], priority: 2, issue_type: "task", assignee: nil, actor: nil)
    rpc("create", {
      title:,
      description:,
      labels:,
      priority:,
      issue_type:,
      assignee:
    }.compact, actor: actor)
  end

  def update(id, status: nil, title: nil, description: nil, priority: nil, assignee: nil, add_labels: nil, remove_labels: nil)
    args = { id:, status:, title:, description:, priority:, assignee:, add_labels:, remove_labels: }.compact
    rpc("update", args)
  end

  def close(id, reason: nil)
    rpc("close", { id:, reason: }.compact)
  end

  # Label operations
  def add_label(id, label)
    rpc("label_add", { id:, label: })
  end

  def remove_label(id, label)
    rpc("label_remove", { id:, label: })
  end

  # Comment operations
  def add_comment(id, text:, author: nil)
    rpc("comment_add", { id:, text:, author: }.compact)
  end

  def list_comments(id)
    rpc("comment_list", { id: }) || []
  end

  # Ready work (unblocked issues)
  def ready(assignee: nil, priority: nil, limit: nil)
    rpc("ready", { assignee:, priority:, limit: }.compact) || []
  end

  # Mutations for real-time sync
  def get_mutations(since:)
    rpc("get_mutations", { since: }) || []
  end

  # Stats
  def stats
    rpc("stats", {})
  end

  # Check if daemon is running
  def daemon_running?
    ping
    true
  rescue DaemonNotRunningError, ConnectionError
    false
  end

  # Ensure daemon is running, starting it if necessary
  def ensure_daemon_running
    return if daemon_running?

    start_daemon
    wait_for_daemon
  end

  private
    def socket_path
      @socket_path ||= find_socket_path
    end

    def find_socket_path
      sock = File.join(@repo_path, ".beads", "bd.sock")
      return sock if File.exist?(sock)

      # Check home directory as fallback
      home_sock = File.join(Dir.home, ".beads", "bd.sock")
      return home_sock if File.exist?(home_sock)

      # Return expected local path even if doesn't exist yet
      sock
    end

    def rpc(operation, args, actor: nil)
      ensure_daemon_running unless operation == "ping"

      request = {
        operation:,
        args:,
        cwd: @repo_path
      }
      request[:actor] = actor if actor.present?

      send_request(request)
    end

    def send_request(request)
      socket = connect_socket
      begin
        # Send request as newline-delimited JSON
        socket.write(JSON.generate(request) + "\n")

        # Read response
        response_line = socket.gets
        raise Error, "Daemon closed connection without responding" if response_line.nil?

        response = JSON.parse(response_line)

        unless response["success"]
          raise Error, response["error"] || "Unknown error"
        end

        parse_data(response["data"])
      ensure
        socket.close
      end
    end

    def connect_socket
      require "socket"
      path = socket_path

      unless File.exist?(path)
        # Try to start the daemon automatically
        start_daemon
        wait_for_daemon
      end

      begin
        socket = UNIXSocket.new(path)
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [SOCKET_TIMEOUT, 0].pack("l_2"))
        socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, [SOCKET_TIMEOUT, 0].pack("l_2"))
        socket
      rescue Errno::ECONNREFUSED, Errno::ENOENT => e
        raise ConnectionError, "Failed to connect to daemon at #{path}: #{e.message}"
      end
    end

    def parse_data(data)
      return nil if data.nil?
      return data unless data.is_a?(String)

      JSON.parse(data)
    rescue JSON::ParserError
      data
    end

    def start_daemon
      beads_dir = File.join(@repo_path, ".beads")
      unless File.directory?(beads_dir)
        raise Error, "No .beads directory found at #{@repo_path}. Run 'bd init' first."
      end

      # Check if it's a git repo (required for daemon)
      unless File.directory?(File.join(@repo_path, ".git"))
        raise Error, "Beads daemon requires a git repository. Run: cd #{@repo_path} && git init && bd doctor"
      end

      # Start daemon in background
      Rails.logger.info("BeadsClient: Starting daemon for #{@repo_path}")
      result = system("bd", "daemon", "start", "--cwd", @repo_path, out: File::NULL, err: File::NULL)
      Rails.logger.info("BeadsClient: Daemon start result: #{result}")
    end

    def wait_for_daemon
      deadline = Time.now + DAEMON_START_TIMEOUT
      while Time.now < deadline
        return if File.exist?(socket_path) && daemon_running?
        sleep 0.1
      end

      raise DaemonNotRunningError, "Daemon failed to start within #{DAEMON_START_TIMEOUT} seconds. Check #{File.join(@repo_path, '.beads', 'daemon.log')} for details."
    end
end
