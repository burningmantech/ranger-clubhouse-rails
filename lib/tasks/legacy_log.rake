# frozen_string_literal: true

namespace :legacy_log do
  desc "Convert the Clubhouse 1 log into legacy_log (DRY_RUN=1 writes nothing; FROM_ID and TO_ID bound the ids)"
  task convert: :environment do
    # `log` is not in the schema (DropLog): it is here only once restored.
    abort "No log table in this database. Restore the Clubhouse 1 log here first." unless Clubhouse1Log.table_exists?

    LegacyLog::Conversion.new(
      from_id: ENV["FROM_ID"].presence&.to_i,
      to_id: ENV["TO_ID"].presence&.to_i,
      dry_run: ENV["DRY_RUN"] == "1"
    ).run
  end
end
