# frozen_string_literal: true

# Matches a pasted list of callsigns and email addresses against person
# records.
#
# Each line is matched one way: a line with an @ must equal a person's email
# address, and any other line is compared as a callsign with capitalisation,
# punctuation, and accents ignored. Lines that match no one come back in
# not_found exactly as typed, and a callsign shared by more than one person
# comes back in ambiguous rather than landing on a guess, so every line is
# accounted for.
class BulkLookupReport
  # The columns the page and the exports read, spelled out so a large list
  # does not drag every column of the person table along.
  COLUMNS = %i[id callsign callsign_normalized status first_name preferred_name
               last_name email vintage years_as_ranger home_phone street1 apt
               street2 city state zip country].freeze

  Results = Struct.new(:found, :not_found, :ambiguous, keyword_init: true) do
    def total = found.size + not_found.size + ambiguous.size
  end

  def self.execute(text)
    input = lines(text)
    matches = matches_for(input)

    results = Results.new(found: [], not_found: [], ambiguous: [])
    input.each do |line|
      people = matches.fetch(line)
      case people.size
      when 1 then results.found << people.first
      when 0 then results.not_found << line
      else results.ambiguous << line
      end
    end
    results
  end

  # Covers the invisible characters that ride along when a list is pasted from
  # a spreadsheet or an email. A plain strip leaves them in place, and a line
  # that looks right would quietly miss.
  STRAY_SPACE = /\A[[:space:]\u200B\uFEFF]+|[[:space:]\u200B\uFEFF]+\z/

  def self.lines(text)
    return [] unless text.is_a?(String)

    text.lines.map { |line| line.gsub(STRAY_SPACE, "") }.reject(&:empty?)
  end

  # Who each distinct line matches: one query resolves all the email lines and
  # one resolves all the callsign lines. A line of nothing but punctuation
  # normalizes to an empty key, is excluded from the query, and so lands in
  # not_found like any other miss.
  def self.matches_for(input)
    emails, callsigns = input.uniq.partition { |line| line.include?("@") }
    keys = callsigns.to_h { |line| [line, WordUtils.normalize_word(line)] }

    # Both group keys are downcased: the database compares these columns
    # without regard to case, and stored values are not reliably lowercase,
    # so the in-memory grouping has to forgive case the same way.
    by_email = people_where(email: emails).group_by { |person| person.email.downcase }
    by_key = people_where(callsign_normalized: keys.values.reject(&:empty?))
             .group_by { |person| person.callsign_normalized.downcase }

    emails.to_h { |line| [line, by_email[line.downcase] || []] }
          .merge(callsigns.to_h { |line| [line, by_key[keys[line]] || []] })
  end

  def self.people_where(condition)
    Person.where(condition).select(*COLUMNS)
  end
end
