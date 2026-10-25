# frozen_string_literal: true

# Recording one certification for a list of callsigns, with the card number and
# the two dates that go with it.
#
# Upstream's CertificationHandler, and the one handler whose action is not known
# until the page has read the database: there is an id per Certification row
# ("cert-12"), not an id per handler, so a certification added tomorrow is
# offered without a deploy and this class only has to work out which row it was
# handed.
class BulkUpload::CertificationHandler < BulkUpload::Handler
  ID_PREFIX = "cert-"

  # The three columns a line may carry after the callsign, in the order they are
  # written. Positional, so the card number keeps its place whether or not the
  # dates around it were filled in.
  COLUMNS = %i[issued_on card_number trained_on].freeze

  # Upstream's wording for the "already exists" sentence, in upstream's field
  # order -- which is not the line's order. Kept as it reads there: this is the
  # sentence a reader checks against what they pasted, and the two applications
  # should not word the same warning differently.
  FIELD_LABELS = { card_number: "Card number",
                   trained_on: "Trained on date",
                   issued_on: "Issued on date" }.freeze

  # Which certification this action records, resolved once for the whole list.
  #
  # A page builds these ids from the table it has just read, so an id naming a
  # row that is not there is a wiring mistake rather than a bad line: it fails
  # at the top instead of turning every callsign on the list into a problem.
  def initialize(...)
    super
    @certification = Certification.find_by(id: action.id.delete_prefix(ID_PREFIX))
    return if @certification

    raise ArgumentError, "#{self.class} cannot record unknown certification [#{action.id}]"
  end

  # One query for everyone on the list who already holds this certification.
  # Full rows, not a projection: apply assigns to these same objects, and the
  # fields it leaves alone have to survive the save.
  def preload(entries)
    @existing = PersonCertification.where(certification_id: @certification.id, person_id: ids(entries))
                                   .index_by(&:person_id)
  end

  def decide(entry)
    fields, problem = parse(entry)
    return entry.decide(:invalid, problem) if problem
    return entry.decide(:change, records(fields)) unless @existing.key?(entry.person.id)

    # Upstream saves this row anyway -- an empty update that only moves
    # updated_at -- and then reports it as a change. There is nothing to write,
    # so nothing is written and the row says so.
    if fields.empty?
      return entry.decide(:no_change, "Certification already exists. Nothing to update.")
    end

    entry.decide(:replace, "Certification already exists. #{field_list(fields).upcase_first} will be updated.")
  end

  # Only the supplied fields are assigned, so a re-run carrying just a card
  # number cannot wipe the dates recorded by the run before it. Nothing on this
  # page can clear a value that is already there; the per-person certification
  # form is where a wrong date gets corrected.
  def apply(entry)
    fields, = parse(entry)

    record = @existing[entry.person.id] ||
             PersonCertification.new(person_id: entry.person.id,
                                     certification_id: @certification.id,
                                     recorder_id: Current.person_id)

    record.assign_attributes(fields)
    record.audit_reason = reason
    record.save!
  end

  private

  # The line's columns as the attributes it actually supplies, plus the sentence
  # explaining why it cannot be used. Called by both decide and apply rather
  # than cached on the entry: three columns of string splitting is cheaper than
  # a second place for the two steps to disagree about what the line said.
  #
  # A blank column means "leave that field alone", which is what makes
  # "hubcap,,12345" -- a card number and neither date -- the ordinary case
  # rather than a special one.
  def parse(entry)
    values = columns(entry)
    if values.size > COLUMNS.size
      return [nil, "A line takes a callsign and at most three fields: issued on date, card number, trained on date"]
    end

    issued_on, card_number, trained_on = values
    fields = {}
    fields[:card_number] = card_number if card_number.present?

    # Validated in the order they are typed, so a line with two bad dates names
    # the first one the reader would look at.
    { issued_on:, trained_on: }.each do |name, value|
      next if value.blank?

      date = to_date(value)
      return [nil, "Invalid #{name.to_s.tr("_", " ")} date"] unless date

      fields[name] = date
    end

    [fields, nil]
  end

  # Anything Date.parse understands, which is a good deal more than the
  # YYYY-MM-DD the help text asks for -- upstream's Carbon::parse is just as
  # loose, and tightening it further would refuse lines the other application
  # accepts. The stated format is what to type, not what is enforced.
  #
  # The one shape refused is a bare run of digits that is not a compact ISO
  # date. Date.parse("12345") answers 2012-12-10 rather than raising, and the
  # line the page's own help advertises for a card number -- "hubcap,,12345" --
  # is one dropped column away from "hubcap,12345", which then recorded a date
  # no one meant and never recorded the card number at all. Eight digits is
  # still a date, because YYYYMMDD is one.
  DIGITS_ONLY = /\A\d+\z/

  def to_date(value)
    return nil if value.match?(DIGITS_ONLY) && value.length != 8

    Date.parse(value)
  rescue Date::Error
    nil
  end

  # The supplied fields with their values, in upstream's field order. The values
  # and not just the field names: what a reader checks the preview against is
  # the list they pasted, and a column that landed in the wrong field is only
  # catchable if the row says what it read.
  def field_list(fields)
    FIELD_LABELS.filter_map { |name, label| "#{label.downcase} #{fields[name]}" if fields.key?(name) }
                .to_sentence
  end

  def records(fields)
    return "Records the certification, with no dates and no card number." if fields.empty?

    "Records #{field_list(fields)}."
  end
end
