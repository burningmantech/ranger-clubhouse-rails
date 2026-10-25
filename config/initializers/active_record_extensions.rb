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
