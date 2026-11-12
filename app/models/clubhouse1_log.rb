# frozen_string_literal: true

# The audit log written by the very first version of the Clubhouse, 16 July
# 2008 to 24 October 2019. The `log` table is no longer part of this
# application's schema (DropLog, 2026-11-12): it exists only in a database
# where the maintainer has restored it, to run `bin/rails legacy_log:convert`
# (LegacyLog::Conversion), the one reader of this class. No page shows it.
class Clubhouse1Log < ApplicationRecord
  self.table_name = "log"

  # The database fills in `occurred`, and there are no created_at/updated_at
  # columns.
  self.record_timestamps = false

  # Nothing writes here. The log closed in 2019.
  def readonly?
    true
  end
end
