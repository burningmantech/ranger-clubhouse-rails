# frozen_string_literal: true

module Admin::BugReportsHelper
  # The browser in a few words -- "Chrome 126 · Mac OS X 10.15.7" -- for a
  # column that has no room for the whole user agent. The whole of it is in
  # the detail row.
  def bug_report_browser(row)
    return "-" if row.user_agent.blank?

    agent = UserAgentParser.parse(row.user_agent)
    browser = [agent.family, agent.version&.major].compact.join(" ")
    "#{browser} · #{agent.os}"
  end
end
