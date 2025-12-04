class Event < ApplicationRecord
  include Notifiable, Particulars, Promptable

  belongs_to :account, default: -> { board.account }
  belongs_to :board
  belongs_to :creator, class_name: "User"
  belongs_to :eventable, polymorphic: true, optional: true

  has_many :webhook_deliveries, class_name: "Webhook::Delivery", dependent: :delete_all

  scope :chronologically, -> { order created_at: :asc, id: :desc }
  scope :preloaded, -> {
    # Note: We can't eagerly load eventable associations when BeadsIssue events are present
    # since BeadsIssue is not an ActiveRecord model. This may cause N+1 queries for Card
    # associations, but it's acceptable given the timeline loads a limited number of events.
    includes(:creator, :board)
  }

  after_create -> { eventable.event_was_created(self) if eventable.respond_to?(:event_was_created) }
  after_create_commit :dispatch_webhooks

  def eventable
    if eventable_type == "BeadsIssue"
      fetch_beads_issue
    else
      super
    end
  end

  def card
    if eventable_type == "BeadsIssue"
      # BeadsIssue events without beads_issue_id are from before the fix
      # Return a placeholder or skip rendering
      eventable || NullBeadsIssue.new
    else
      eventable.respond_to?(:card) ? eventable.card : eventable
    end
  end

  def action
    super.inquiry
  end

  def notifiable_target
    eventable
  end

  def description_for(user)
    Event::Description.new(self, user)
  end

  private
    def dispatch_webhooks
      Event::WebhookDispatchJob.perform_later(self)
    end

    def fetch_beads_issue
      return @beads_issue if defined?(@beads_issue)
      return nil unless beads_issue_id

      issue_data = board.beads_client.show(beads_issue_id)
      @beads_issue = BeadsIssue.new(issue_data)
      @beads_issue.board = board
      @beads_issue
    rescue BeadsClient::Error => e
      Rails.logger.error("Event: Failed to fetch BeadsIssue #{beads_issue_id}: #{e.message}")
      nil
    end
end
