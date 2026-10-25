# frozen_string_literal: true

# Every account, grouped by the status it holds right now.
class PeopleByStatusReport
  # How many people hold each status, keyed by status, in the order
  # Person::ALL_STATUSES lists them. A status no one holds counts zero rather
  # than dropping out -- a missing status reads as a hole in the report.
  def self.counts
    tallied = Person.group(:status).count
    Person::ALL_STATUSES.index_with { |status| tallied[status].to_i }
  end

  # The people holding one status, by callsign.
  def self.people(status)
    Person.by_status(status).basic_info.order(:callsign)
  end

  # The status an address names, or nil. Slugs come from the statuses
  # themselves, so the list can never drift from what may be stored.
  def self.find_status(slug)
    Person::ALL_STATUSES.find { |status| self.slug(status) == slug.to_s }
  end

  def self.slug(status) = status.parameterize
end
