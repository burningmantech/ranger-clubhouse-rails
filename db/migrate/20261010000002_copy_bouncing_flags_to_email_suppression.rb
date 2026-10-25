# frozen_string_literal: true

# Copies person.is_bouncing into email_suppression, dated from the bounce logs:
# see EmailSuppression.copy_bouncing_flags. When the column is removed, that
# method goes with it and this up is emptied.
class CopyBouncingFlagsToEmailSuppression < ActiveRecord::Migration[8.1]
  def up
    refuse_mismatched_clocks

    copied, skipped = EmailSuppression.copy_bouncing_flags
    say "#{copied} bouncing addresses copied, #{skipped} skipped"
  end

  def down
    # Nothing to undo: rolling back CreateEmailSuppression drops the table and these rows.
  end

  private

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
