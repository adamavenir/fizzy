# Null object for BeadsIssue events that can't be loaded
# Used when beads_issue_id is missing or the issue can't be fetched
class NullBeadsIssue
  def id
    "unknown"
  end

  def title
    "[Beads Issue - Could not load]"
  end

  def number
    "?"
  end

  def closed?
    false
  end

  def golden?
    false
  end

  def color
    "var(--color-card-default)"
  end

  def image
    nil
  end

  def to_param
    nil
  end

  def persisted?
    false
  end
end
