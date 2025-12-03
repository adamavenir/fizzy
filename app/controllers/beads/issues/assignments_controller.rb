class Beads::Issues::AssignmentsController < ApplicationController
  before_action :set_board
  before_action :set_issue

  def new
    @card = @issue

    # Get assigned users (exclude current user)
    assigned_user_ids = @issue.assignees.select { |a| a.respond_to?(:id) }.map(&:id).compact
    @assigned_to = @board.users.active.where(id: assigned_user_ids).where.not(id: Current.user)

    # Get unassigned users (exclude current user and already assigned)
    @users = @board.users.active.alphabetically
                  .where.not(id: assigned_user_ids)
                  .where.not(id: Current.user)
  end

  def create
    user = @board.users.active.find(params[:assignee_id])
    email = user.identity.email_address

    # Toggle: if already assigned to this user, unassign; otherwise assign
    if @issue.assignee == email
      @board.beads_client.update(@issue.id, assignee: "")
    else
      @board.beads_client.update(@issue.id, assignee: email)
    end

    # Reload and render
    data = @board.beads_client.show(@issue.id)
    @issue = BeadsIssue.new(data)
    @issue.board = @board
    @card = @issue
  end

  private
    def set_board
      @board = Current.user.boards.find(params[:board_id])
    end

    def set_issue
      data = @board.beads_client.show(params[:issue_issue_id])
      @issue = BeadsIssue.new(data)
      @issue.board = @board
    end
end
