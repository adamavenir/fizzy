module EventsHelper
  def event_action_icon(event)
    case event.action
    when "card_assigned"
      "assigned"
    when "card_unassigned"
      "minus"
    when "comment_created"
      "comment"
    when "card_title_changed"
      "rename"
    when "card_board_changed", "card_triaged", "card_postponed", "card_auto_postponed"
      "move"
    when "beads_issue_updated"
      "rename"
    when "beads_issue_started"
      "bolt"
    when "beads_issue_blocked"
      "close-circle"
    when "beads_issue_assigned"
      "assigned"
    when "beads_issue_unassigned"
      "minus"
    when "beads_comment_created"
      "comment"
    when "beads_issue_title_changed"
      "rename"
    when "beads_issue_description_changed"
      "pencil"
    when "beads_issue_status_changed"
      "move"
    else
      "person"
    end
  end

  def events_at_hour_container(column, hour, &block)
    tag.div class: "events__time-block", style: "grid-area: #{25 - hour}/#{column.index}", &block
  end
end
