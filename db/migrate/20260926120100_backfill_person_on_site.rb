# frozen_string_literal: true

# Fills person_on_site from the person-update audit rows that change on_site.
# The event index narrows action_logs (~3.2M rows) to its ~68k person-update
# rows before anything is read. Clubhouse 2 stored the old value as 0/1 before
# 2020 and left out "id" before May 2020, so only the new value and
# target_person_id are trusted.
class BackfillPersonOnSite < ActiveRecord::Migration[8.1]
  BOOLEAN = ActiveModel::Type::Boolean.new

  # The tables as they are today, whatever the app models become.
  class MigrationActionLog < ActiveRecord::Base
    self.table_name = "action_logs"
  end

  class MigrationPersonOnSite < ActiveRecord::Base
    self.table_name = "person_on_site"
  end

  def up
    refuse_mismatched_clocks

    # A change already logged -- by an earlier run, or by the new code once it
    # serves -- is left alone, so running this again (db:migrate:redo) adds any
    # change the old code made after the first run read the audit rows.
    logged = MigrationPersonOnSite.pluck(:person_id, :action, :created_at)
                                  .to_set { |id, action, at| [id, action, at.to_i] }

    rows = []
    skipped = 0
    already = 0
    say_with_time "Reading on_site changes from action_logs" do
      # Escaped: a bare on_site pattern also matches "On Site" in emergency-contact text.
      MigrationActionLog.select(:id, :person_id, :target_person_id, :created_at, :data)
                        .where(event: "person-update")
                        .where("data LIKE ?", "%#{MigrationActionLog.sanitize_sql_like('"on_site"')}%")
                        .find_each(batch_size: 10_000) do |log|
        row = on_site_row(log)
        if row.nil?
          skipped += 1
        elsif logged?(logged, row)
          already += 1
        else
          rows << row
        end
      end
      rows.size
    end

    # One transaction, in action_logs id order, so person_on_site ids follow history.
    say_with_time "Writing person_on_site" do
      MigrationPersonOnSite.transaction do
        rows.each_slice(1_000) { MigrationPersonOnSite.insert_all(it, record_timestamps: false) }
      end
      rows.size
    end

    on_site = rows.count { it[:action] == "on-site" }
    say "#{on_site} on-site, #{rows.size - on_site} off-site, #{skipped} skipped, " \
        "#{already} already logged"
  end

  def down
    # Nothing to undo: rolling back CreatePersonOnSite drops the table and these rows.
  end

  private

  # action_logs.created_at is a TIMESTAMP, which MariaDB reads out on its own
  # clock, while person_on_site keeps the app's. Were the two to differ, every
  # copied row would be shifted for good. January and July both, so a zone that
  # keeps daylight time is caught as well.
  def refuse_mismatched_clocks
    [Time.local(2026, 1, 15, 12), Time.local(2026, 7, 15, 12)].each do |time|
      sql = "SELECT UNIX_TIMESTAMP(#{connection.quote(time.strftime('%F %T'))})"
      next if connection.select_value(sql).to_i == time.to_i

      raise "The database and the app keep different clocks. " \
            "Give both the same TZ, then run this again."
    end
  end

  # The hook writes its row a moment after the audit row, so a change it logged
  # can sit a second later.
  def logged?(logged, row)
    at = row[:created_at].to_i
    [at, at + 1].any? { logged.include?([row[:person_id], row[:action], it]) }
  end

  # nil when the row is not a real on_site change.
  def on_site_row(log)
    data = JSON.parse(log.data.to_s)
    return unless data.is_a?(Hash) && data["on_site"].is_a?(Array)

    from, to = data["on_site"].map { BOOLEAN.cast(it) }
    return if to.nil? || from == to || log.target_person_id.nil?

    { person_id: log.target_person_id, creator_person_id: log.person_id, action: to ? "on-site" : "off-site",
      created_at: log.created_at }
  rescue JSON::ParserError
    nil
  end
end
