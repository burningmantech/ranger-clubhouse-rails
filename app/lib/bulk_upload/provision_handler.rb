# frozen_string_literal: true

# Granting one provision -- a meal pass, a shower, or an event radio -- to every
# callsign on the list, either earned or allocated.
#
# Upstream's ProvisionHandler, serving the same thirteen action ids. Earned and
# allocated are the same write with two different sets of rules: an earned
# provision is credited to the season it was rangered in and lasts several
# years, an allocated one is handed out for this year and dies with it, which is
# why an allocated line may carry nothing but a callsign.
#
# There is no "no change" here. A provision is a countable thing rather than a
# flag, so a person who already has one is not already in the desired state --
# the old one is cancelled and a new one takes its place, which is why every
# line either writes or is refused.
class BulkUpload::ProvisionHandler < BulkUpload::Handler
  ALLOCATED_PREFIX = "alloc_"

  # The seven meal passes a reader can choose by name, and the three booleans
  # each one actually is.
  #
  # CONSTRAINT: `provision` has three types, and "all eat pass" is not one of
  # them. Every pass is a MEALS row plus a combination of period flags, so two
  # provisions are only the same pass when all three flags match -- which is
  # what the duplicate query below compares, and why it cannot just match on
  # type the way the shower and radio lookups do.
  #
  # "event_post_event_eat_pass" does say "event" twice. It is upstream's id, and
  # the history rows already written under it are the reason it is not tidied.
  MEAL_PERIODS = {
    "all_eat_pass" => { pre_event_meals: true, event_week_meals: true, post_event_meals: true },
    "event_eat_pass" => { pre_event_meals: false, event_week_meals: true, post_event_meals: false },
    "pre_event_eat_pass" => { pre_event_meals: true, event_week_meals: false, post_event_meals: false },
    "post_event_eat_pass" => { pre_event_meals: false, event_week_meals: false, post_event_meals: true },
    "pre_event_event_eat_pass" => { pre_event_meals: true, event_week_meals: true, post_event_meals: false },
    "event_post_event_eat_pass" => { pre_event_meals: false, event_week_meals: true, post_event_meals: true },
    "pre_post_eat_pass" => { pre_event_meals: true, event_week_meals: false, post_event_meals: true }
  }.freeze

  ALLOCATED_ONLY_CALLSIGN = "Allocated provisions uploads only take a callsign and no other parameters."

  EARNED_LINE_FORMAT = "Unexpected additional data. An earned line takes a callsign and " \
                       "at most a source year and an expiry year."

  # Upstream's comment on the new row, kept verbatim: it is what an admin reading
  # a provision's comments in either application already looks for.
  NEW_PROVISION_COMMENT = "created via bulk uploader"

  # What one line turned out to be asking for. Built once by `read` and used by
  # both passes, so the years the preview printed are the years the apply saves.
  Grant = Struct.new(:source_year, :expiry_year, :item_count, keyword_init: true)

  # The id decides everything about this handler, so an id it cannot serve is a
  # boot-time mistake rather than a line the reader gets blamed for.
  def initialize(...)
    super
    @allocated = action.id.start_with?(ALLOCATED_PREFIX)
    @kind = action.id.delete_prefix(ALLOCATED_PREFIX)
    @periods = MEAL_PERIODS[@kind]
    return if @periods || [Provision::WET_SPOT, Provision::EVENT_RADIO].include?(@kind)

    raise ArgumentError, "#{self.class} cannot grant provision [#{action.id}]"
  end

  # One query for what every line would land on top of.
  #
  # Provision.find_available_type_for_person and .find_available_meals_for_person
  # ask exactly this question, but one person at a time; a 300-callsign paste
  # would run 300 of them for the preview and 300 more for the apply.
  #
  # Ordered where upstream's keyBy takes whichever row the database happened to
  # return last. Two matching current provisions is a state that exists in the
  # data, and the preview has to name the same one the apply cancels.
  def preload(entries)
    scope = Provision.where(person_id: ids(entries), type: provision_type,
                            status: Provision::CURRENT_STATUSES, is_allocated: @allocated)
    scope = scope.where(@periods) if meals?

    @existing = scope.order(:id).group_by(&:person_id)
  end

  def decide(entry)
    grant, problem = read(entry)
    return entry.decide(:invalid, problem) if problem

    existing = existing_for(entry)
    return entry.decide(:replace, "#{replacement_note(existing)} #{summary(grant).upcase_first}.") if existing.any?

    entry.decide(:change, "#{summary(grant).upcase_first}.")
  end

  # The new row first, so the cancelled ones can name it. All the writes are
  # already inside the transaction the batch opened, so a failure on any of them
  # leaves none behind.
  #
  # Every current provision is cancelled, not just the first: two matching rows
  # is a state that exists in the data, and cancelling one of them would leave
  # the person holding more provisions after the run than before it, which is
  # the opposite of what the preview promised.
  def apply(entry)
    grant, = read(entry)
    existing = existing_for(entry)

    provision = create_provision(entry.person.id, grant)
    existing.each { |item| cancel(item, provision) }
  end

  private

  def meals? = !@periods.nil?

  def event_radio? = @kind == Provision::EVENT_RADIO

  def provision_type = meals? ? Provision::MEALS : @kind

  def existing_for(entry) = @existing[entry.person.id] || []

  # Reads the line's columns.
  #
  # @return [Array(Grant, nil), Array(nil, String)] the grant, or the sentence
  #   saying why the line cannot be used
  def read(entry)
    values = columns(entry)
    item_count = 1

    # The radio count is taken FIRST, before the allocated check below rejects
    # any column at all. Upstream's ordering, and deliberate: an allocated radio
    # line has no other way to say how many radios it is for.
    if event_radio? && values.any?
      item_count = whole_number(values.shift)
      return [nil, "Item count is not a number"] if item_count.nil?
    end

    source_year, expiry_year = starting_years
    return [nil, ALLOCATED_ONLY_CALLSIGN] if @allocated && values.any?
    return [Grant.new(source_year:, expiry_year:, item_count:), nil] if @allocated

    # Refused rather than ignored, as every sibling handler does: a column that
    # is silently dropped is how a reader comes away believing something they
    # typed took effect.
    return [nil, EARNED_LINE_FORMAT] if values.size > 2

    # Counted, not checked for content: an interior blank ("hubcap,,2030") is a
    # year that was meant to be there, and upstream refuses it rather than
    # quietly falling back to the default. A trailing blank never gets this far
    # -- `columns` has already dropped it, so "hubcap," is a bare callsign.
    if values.size >= 1
      source_year, problem = check_year_range(values[0], source: true)
      return [nil, problem] if problem
    end

    if values.size >= 2
      expiry_year, problem = check_year_range(values[1], source: false)
      return [nil, problem] if problem
    end

    # Only reachable on an earned line: an allocated grant's source year is
    # forced to this year, which is never after its expiry.
    if expiry_year < source_year
      return [nil, "Source year [#{source_year}] is after expiry year [#{expiry_year}]"]
    end

    [Grant.new(source_year:, expiry_year:, item_count:), nil]
  end

  # An allocated provision is for this year whatever month it is granted in, and
  # the model expires it with the year regardless of what is passed
  # (set_expires_on_for_allocated), which is why the page asks for no years on
  # an allocated line.
  def starting_years
    source_year, expiry_year = self.class.default_years
    @allocated ? [year, expiry_year] : [source_year, expiry_year]
  end

  # What the line grants, spelled out. Most lines name no years at all, so these
  # are facts a reader cannot check by reading their own list back -- and the
  # radio count is where a mistyped year silently lands, because the count is
  # the column taken first.
  def summary(grant)
    parts = []
    parts << "#{grant.item_count} #{(grant.item_count == 1) ? "radio" : "radios"}" if event_radio?
    parts << if @allocated
               "allocated for #{year}"
             else
               "source year #{grant.source_year}, expires #{grant.expiry_year}"
             end

    parts.join(", ")
  end

  # The rows a reader should stop on: this line writes over something that is
  # already there. Earned provisions name the year the existing one was earned,
  # because that is what tells an admin whether they are about to cancel this
  # season's grant or last season's.
  def replacement_note(existing)
    held = if @allocated
             "#{existing.first.type_label} allocated"
           else
             "#{existing.first.type_label} earned in #{existing.map(&:source_year).uniq.sort.join(" and ")}"
           end

    return "Already has #{held}. The existing item will be cancelled and replaced." if existing.one?

    "Already has #{existing.size} of #{held}. All #{existing.size} will be cancelled and replaced."
  end

  # expires_on takes a bare year: the model's setter expands it to that
  # September's 15th, which is the date every other provision in the table
  # carries.
  def create_provision(person_id, grant)
    provision = Provision.new(person_id:, type: provision_type, status: Provision::AVAILABLE,
                              source_year: grant.source_year, expires_on: grant.expiry_year,
                              is_allocated: @allocated)
    provision.item_count = grant.item_count if event_radio?
    provision.assign_attributes(@periods) if meals?
    provision.additional_comments = NEW_PROVISION_COMMENT
    # Upstream hardcodes its audit reason here and drops whatever the reader
    # typed. The page asks for a reason; the record keeps it.
    provision.audit_reason = reason
    provision.save!
    provision
  end

  # Saved without validation, as upstream does: this row was created by someone
  # else, possibly by hand, and a rule it fails today must not be able to keep it
  # alive alongside its replacement.
  def cancel(existing, replacement)
    note = "Replaced by item ##{replacement.id} via bulk uploader"
    existing.status = Provision::CANCELLED
    existing.additional_comments = note
    existing.audit_reason = note
    existing.save!(validate: false)
  end
end
