# frozen_string_literal: true

class DailyReportMailer < ApplicationMailer
  # Each listing in the report, in the order it appears. The template draws them
  # all the same way, so a new listing only needs a line here and a method that
  # turns one record into its cells.
  LISTINGS = [
    { key: :error_logs, title: "Error Logs", row: :error_log_row,
      headers: ["Timestamp (UTC-7)", "Person", "Type", "IP", "URL"],
      empty: "No errors were logged." },
    { key: :failed_jobs, title: "Failed Background Tasks", row: :failed_job_row,
      headers: ["Timestamp (UTC-7)", "Task", "Error"],
      empty: "No tasks failed.",
      unavailable: "This server cannot reach the queue, so failed tasks cannot be listed." },
    { key: :unknown_phones, title: "Unknown Phone Numbers", row: :unknown_phone_row,
      headers: ["Timestamp (UTC-7)", "Phone", "Message"],
      empty: "No unknown phones numbers texted to the RBS number." },
    { key: :email_issues, title: "Email Issues", row: :email_issue_row,
      headers: ["Timestamp (UTC-7)", "Person", "Event", "To Email"],
      empty: "No errors were logged." },
    { key: :setting_logs, title: "Setting Changes", row: :setting_log_row,
      headers: ["Timestamp (UTC-7)", "User", "Setting", "Values"],
      empty: "No settings were changed" },
    { key: :role_logs, title: "Manual Permission Changes", row: :role_log_row,
      headers: ["Timestamp (UTC-7)", "Callsign", "Source", "Permission(s)", "Reason"],
      empty: "No manual permission changes happened." },
    { key: :status_logs, title: "Status Changes", row: :status_log_row,
      headers: ["Timestamp (UTC-7)", "Callsign", "Source", "Old", "New", "Reason"],
      empty: "No status changes happened." },
    { key: :failed_broadcasts, title: "Failed Broadcasts", row: :failed_broadcast_row,
      headers: ["Timestamp (UTC-7)", "Sender", "Alert", "People", "Delivery", "Retried?"],
      empty: "No broadcast failures." }
  ].freeze

  # Which stored setting answers each row of the settings table.
  WATCHED_SETTINGS = {
    dashboard_period: "DashboardPeriod",
    online_course_enabled: "OnlineCourseEnabled",
    photo_upload_enable: "PhotoUploadEnable",
    online_course_disabled_allow_signups: "OnlineCourseDisabledAllowSignups",
    ticketing_period: "TicketingPeriod",
    timesheet_correction_enable: "TimesheetCorrectionEnable",
    training_seasonal_role_enabled: "TrainingSeasonalRoleEnabled",
    event_management_on_playa_enabled: "EventManagementOnPlayaEnabled"
  }.freeze

  def notify(failed_broadcasts:, error_logs:, role_logs:, status_logs:, settings:, setting_logs:,
             email_issues:, dashboard_period:, failed_jobs:, unknown_phones:)
    records = { error_logs:, failed_jobs:, unknown_phones:, email_issues:,
                setting_logs:, role_logs:, status_logs:, failed_broadcasts: }

    liquid_assigns.merge!(
      report_date: Date.current.strftime("%Y-%m-%d"),
      generated_at: Time.current.to_s,
      dashboard_period: dashboard_period,
      settings: WATCHED_SETTINGS.transform_values { |name| settings[name] },
      sections: LISTINGS.map { |listing| section(listing, records[listing[:key]]) }
    )

    mail(
      from: do_not_reply_from,
      to: build_addresses(Setting.get_value(Setting::DAILY_REPORT_EMAIL)),
      subject: liquid_subject
    )
  end

  private

  # One listing, ready to draw. Records that could not be looked up at all say so
  # instead of showing an empty listing, which would read as good news.
  def section(listing, records)
    values = listing.slice(:title, :headers, :empty)
    return values.merge(unavailable: listing[:unavailable]) if records.nil?

    values.merge(rows: records.map { |record| send(listing[:row], record) })
  end

  def error_log_row(log)
    [log.created_at.to_s, log.person&.callsign || "-", log.error_type, log.ip, log.url]
  end

  def failed_job_row(failed)
    [failed.at.to_s, failed.task, failed.reason]
  end

  def unknown_phone_row(phone)
    [phone.created_at.to_s, phone.address, phone.message]
  end

  def email_issue_row(log)
    person = if log.target_person
               log.target_person.callsign
             elsif log.target_person_id
               "Person ##{log.target_person_id}"
             else
               # The only cell in the report that carries its own markup.
               "<i>- unknown -</i>".html_safe
             end

    [log.created_at.to_s, person, log.event, log.data["to_email"]]
  end

  def setting_log_row(log)
    values = log.data["value"]
    [log.created_at.to_s, source_callsign(log), log.data["name"], "#{values[0]} -> #{values[1]}"]
  end

  def role_log_row(log)
    target = log.target_person&.callsign || "Deleted ##{log.target_person_id}"
    [log.created_at.to_s, target, source_callsign(log), permission_change(log), log.message]
  end

  def status_log_row(log)
    source = if log.person_source
               log.person_source.callsign
             else
               log.person_source_id || "Unknown source, no id"
             end

    [log.created_at.to_s, log.person&.callsign || "Deleted ##{log.person_id}", source.to_s,
     log.old_status, log.new_status, log.reason]
  end

  def failed_broadcast_row(log)
    [log.created_at.to_s,
     log.sender&.callsign || "Deleted ##{log.sender_id}",
     broadcast_alert(log),
     log.recipient_count,
     [("SMS" if log.sent_sms), ("email" if log.sent_email), ("CH" if log.sent_clubhouse)].compact.join(" "),
     broadcast_retry(log)]
  end

  # Whoever made the change, however little is left of them.
  def source_callsign(log)
    log.person&.callsign || log.person_id&.to_s || "-"
  end

  def permission_change(log)
    return "" unless %w[person-role-add person-role-remove].include?(log.event)

    word = log.event == "person-role-add" ? "ADDED" : "REMOVED"
    named = log.roles.blank? ? "(deleted roles) #{log.data["role_ids"].to_json}" : log.roles.map(&:title).join(", ")
    "#{word}: #{named}"
  end

  def broadcast_alert(log)
    return "Deleted ##{log.alert_id}" if log.alert.nil?

    "#{log.alert.on_playa ? "On Playa" : "Pre-Event"}: #{log.alert.title}"
  end

  def broadcast_retry(log)
    return "No retry attempt" if log.retry_at.nil?

    "Retry at #{log.retry_at} by #{log.retry_person&.callsign || "Deleted ##{log.retry_person_id}"}"
  end
end
