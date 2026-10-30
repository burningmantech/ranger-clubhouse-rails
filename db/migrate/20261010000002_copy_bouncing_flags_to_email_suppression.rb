# frozen_string_literal: true

# Copies person.is_bouncing into email_suppression, dated from the bounce logs.
# A flag said only that one Permanent bounce came back since the address last
# changed, and Clubhouse 2 never acted on it, so one may be years stale. Each
# flag is copied only when a Permanent email-bouncing log names the person's
# current address, dated from the first and last of those logs; Clubhouse 2
# wrote one with each flag and never pruned them. An address that already has
# a row is left as it is, so running this again adds nothing.
#
# Self-contained since 2026-10-29, when the column was dropped
# (DropLegacyPersonColumns) and EmailSuppression.copy_bouncing_flags with it:
# a database that has not run this yet still gets its copy before the drop.
class CopyBouncingFlagsToEmailSuppression < ActiveRecord::Migration[8.1]
  class MigrationPerson < ActiveRecord::Base
    self.table_name = "person"
  end

  class MigrationActionLog < ActiveRecord::Base
    self.table_name = "action_logs"
  end

  class MigrationEmailSuppression < ActiveRecord::Base
    self.table_name = "email_suppression"
  end

  LoggedBounce = Data.define(:id, :created_at, :sub_type, :message_id)

  def up
    refuse_mismatched_clocks

    copied, skipped = copy_bouncing_flags
    say "#{copied} bouncing addresses copied, #{skipped} skipped"
  end

  def down
    # Nothing to undo: rolling back CreateEmailSuppression drops the table and these rows.
  end

  private

  def copy_bouncing_flags
    flagged = MigrationPerson.where(is_bouncing: true).pluck(:id, :email)
    addresses = flagged.to_h { |id, email| [id, normalize(email)] }.compact_blank
    bounces = Hash.new { |hash, person_id| hash[person_id] = [] }

    MigrationActionLog.select(:id, :target_person_id, :created_at, :data)
                      .where(event: "email-bouncing", target_person_id: addresses.keys)
                      .find_each(batch_size: 10_000) do |log|
      bounce = logged_bounce(log, addresses[log.target_person_id])
      bounces[log.target_person_id] << bounce if bounce
    end

    taken = MigrationEmailSuppression.where(email: bounces.keys.map { addresses[it] }).pluck(:email).to_set
    rows = bounces.filter_map do |person_id, logs|
      next if taken.include?(addresses[person_id])

      first, last = logs.minmax_by { [it.created_at, it.id] }
      { email: addresses[person_id], reason: "bounce", sub_type: last.sub_type, message_id: last.message_id,
        first_reported_at: first.created_at, last_reported_at: last.created_at, report_count: logs.size }
    end
    MigrationEmailSuppression.insert_all(rows) if rows.any?

    [rows.size, flagged.size - rows.size]
  end

  # A Permanent bounce of address from one email-bouncing log, or nil for any other.
  def logged_bounce(log, address)
    data = JSON.parse(log.data.to_s)
    return unless data.is_a?(Hash) && data["bounce_type"] == "Permanent"
    return unless normalize(data["to_email"]) == address

    LoggedBounce.new(id: log.id, created_at: log.created_at, message_id: data["message_id"].presence,
                     sub_type: data.dig("message", "bounce", "bounceSubType").presence)
  rescue JSON::ParserError, TypeError
    nil
  end

  def normalize(email) = email.to_s.strip.downcase.presence

  # action_logs.created_at is a TIMESTAMP, which MariaDB reads out on its own
  # clock, while email_suppression keeps the app's. Were the two to differ,
  # every copied date would be shifted for good. January and July both, so a
  # zone that keeps daylight time is caught as well.
  def refuse_mismatched_clocks
    [Time.local(2026, 1, 15, 12), Time.local(2026, 7, 15, 12)].each do |time|
      sql = "SELECT UNIX_TIMESTAMP(#{connection.quote(time.strftime('%F %T'))})"
      next if connection.select_value(sql).to_i == time.to_i

      raise "The database and the app keep different clocks. " \
            "Give both the same TZ, then run this again."
    end
  end
end
