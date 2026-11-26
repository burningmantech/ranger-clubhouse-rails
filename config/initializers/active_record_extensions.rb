module GlobalRelationExtensions
  # Selects the same rows as YEAR(column) BETWEEN first AND last, but as a
  # range so MariaDB can use an index — it cannot index a function on a column,
  # so the YEAR() form always scans the table.
  #
  # Time.local, not Time.zone: datetimes are stored as machine-local wall clock
  # (config.active_record.default_timezone = :local) while Time.zone is Phoenix,
  # so a Time.zone boundary would serialize an hour early and drag in the
  # previous year's last hour.
  def where_years(column, first, last)
    where("#{column} >= ? AND #{column} < ?", Time.local(first), Time.local(last + 1))
  end

  # The rows YEAR(column) = year selects.
  def where_year(column, year) = where_years(column, year, year)

  def where_like(column, match)
    where("#{column} LIKE ?", match)
  end
end

ActiveRecord::Relation.include(GlobalRelationExtensions)

# A table created without a charset takes its database's default, and this
# app's databases do not share one: where the servers' tables were created it
# was latin1, a development copy takes its MariaDB's, and Rails gives a test
# database a third. So create_table names utf8mb4 / utf8mb4_unicode_ci itself,
# unless the caller names a charset or a collation.
# test/lib/table_charset_test.rb holds db/schema.rb to the same.
module Utf8mb4TableDefault
  def create_table(table_name, **options)
    unless options.key?(:charset) || options.key?(:collation)
      options.merge!(charset: "utf8mb4", collation: "utf8mb4_unicode_ci")
    end
    super
  end
end

ActiveSupport.on_load(:active_record_mysql2adapter) { prepend Utf8mb4TableDefault }
