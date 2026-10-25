# frozen_string_literal: true

module MailLogHelper
  # What the two row icons are called. The icon on a row carries the word as its
  # tooltip and its screen-reader text, and the legend in the page's card prints
  # the same word beside a sample, so the two cannot drift.
  BOUNCED_LABEL = "Bounced"
  SPAM_LABEL = "Marked as spam"

  # How far back the log goes, as the sentence both mail logs print: in each
  # page's card, and in an empty state that may be empty for this reason alone.
  # The window is read off MailLog::RETENTION part by part, so it says
  # "6 months" today and "90 days" if the cleanup is ever set that way.
  def mail_log_retention_note
    "Only the last #{mail_log_retention_window} of messages are kept."
  end

  # The third stat box counts that same window, so it is named by it.
  def mail_log_retained_label
    "Last #{mail_log_retention_window(title_case: true)}"
  end

  # MailLog::RETENTION in words: "6 months" for a sentence, "6 Months" for a label.
  def mail_log_retention_window(title_case: false)
    MailLog::RETENTION.parts.map do |unit, count|
      unit = unit.to_s.singularize
      pluralize(count, title_case ? unit.capitalize : unit)
    end.to_sentence
  end

  # Prepare a mail body for display inside a sandboxed srcdoc iframe.
  # Plain-text bodies would render with collapsed whitespace as HTML, so wrap
  # those in an escaped <pre>. Returns a plain string — the view's srcdoc
  # attribute interpolation applies the (intentional) second level of escaping.
  def mail_body_srcdoc(log)
    body = log.body
    return body if body =~ /<html/i

    "<pre style=\"white-space: pre-wrap; font-family: sans-serif;\">#{ERB::Util.html_escape(body)}</pre>"
  end
end
