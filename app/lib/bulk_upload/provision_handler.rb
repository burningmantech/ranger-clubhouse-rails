# frozen_string_literal: true

# Granting one provision -- a meal pass, a shower, or a radio -- to every
# callsign on the list: earned, allocated, or good for this event only.
#
# Upstream's ProvisionHandler, serving its thirteen action ids plus the two
# radio grants upstream never had (Provision::EVENT_ONLY_TYPES). Earned and
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
  # CONSTRAINT: "all eat pass" is not one of `provision`'s types
  # (Provision::ALL_TYPES). Every pass is a MEALS row plus a combination of
  # period flags, so two
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

  EVENT_ONLY_LINE_FORMAT = "Unexpected additional data. A shift radio or specialized radio line " \
                           "takes a callsign and at most a radio count."

  # Each grant on this page replaces what the person holds, so a second line
  # for the same person would land beside the first line's grant, not on it.
  ONE_LINE_PER_PERSON = "Listed more than once with different details. Keep one line for each person."

  # Far above any real grant and below every year, so a year typed into the
  # count column is refused, and nothing reaches the column it cannot hold.
  MAX_RADIO_COUNT = 99

  # A specialized radio's action id is this plus its asset_group id: one action
  # per group, as the certifications page has one per certification.
  GROUP_PREFIX = "#{Provision::RADIO_GROUP}-"

  # The radio groups this page may grant from. The page lists its actions from
  # these rows and hands the same rows over as context[:radio_groups], so the
  # handler never looks a group up a second time and cannot disagree with the list.
  def self.radio_groups = AssetGroup.active.where(type: Asset::TYPE_RADIO)

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
    if @kind.start_with?(GROUP_PREFIX)
      group_id = @kind.delete_prefix(GROUP_PREFIX)
      @group = context.fetch(:radio_groups, []).find { |group| group.id.to_s == group_id }
      @kind = Provision::RADIO_GROUP
    end
    @periods = MEAL_PERIODS[@kind]
    @event_only = Provision::EVENT_ONLY_TYPES.include?(@kind)
    return if servable?

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
    # A grant from another radio group is a different provision, and stays.
    scope = scope.where(asset_group_id: @group.id) if @group
    # A radio grant of a past event that Clean Provisions has not ended yet is
    # not in force (Provision.radio_grants), so it is not something held.
    scope = scope.unexpired if @event_only

    @existing = scope.order(:id).group_by(&:person_id)
    @granted = Set.new
  end

  def decide(entry)
    grant, problem = read(entry)
    return entry.decide(:invalid, problem) if problem
    # Set#add? answers nil for a person an earlier line already claimed.
    return entry.decide(:invalid, ONE_LINE_PER_PERSON) unless @granted.add?(entry.person.id)

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

  # The model refuses an allocated radio grant, and a specialized radio is
  # nothing without its group.
  def servable?
    return !@allocated && (@kind == Provision::RADIO_SHIFT || !@group.nil?) if @event_only

    meals? || [Provision::WET_SPOT, Provision::EVENT_RADIO].include?(@kind)
  end

  def counted? = Provision::COUNTED_TYPES.include?(@kind)

  # Granted for this year, with no years on the line.
  def this_year_only? = @allocated || @event_only

  def radios(count) = "#{count} #{(count == 1) ? "radio" : "radios"}"

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
    if counted? && values.any?
      item_count = whole_number(values.shift)
      return [nil, "Radio count is not a number."] if item_count.nil?
      return [nil, "Radio count must be 1 or more."] if item_count < 1
      return [nil, "Radio count must be #{MAX_RADIO_COUNT} or fewer."] if item_count > MAX_RADIO_COUNT
    end

    source_year, expiry_year = starting_years
    return [nil, ALLOCATED_ONLY_CALLSIGN] if @allocated && values.any?
    return [nil, EVENT_ONLY_LINE_FORMAT] if @event_only && values.any?
    return [Grant.new(source_year:, expiry_year:, item_count:), nil] if this_year_only?

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

  # An allocated provision or a radio grant is for this year whatever month it
  # is granted in, and the model expires it with the year regardless of what is
  # passed (set_expires_on_for_event_only), which is why the page asks for no
  # years on those lines.
  def starting_years
    source_year, expiry_year = self.class.default_years
    this_year_only? ? [year, expiry_year] : [source_year, expiry_year]
  end

  # What the line grants, spelled out. Most lines name no years at all, so these
  # are facts a reader cannot check by reading their own list back.
  def summary(grant)
    parts = []
    # The group is named here, not only in the action's label: this sentence is
    # also what the commit log keeps, and a group can later be merged away.
    parts << [radios(grant.item_count), ("from #{@group.title}" if @group)].compact.join(" ") if counted?
    parts << if @allocated
               "allocated for #{year}"
             elsif @event_only
               "for the #{year} event"
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
           elsif @event_only
             # The action's label, which is type_label without a query per row.
             "#{action.label} (#{radios(existing.map { |item| item.item_count || 1 }.max)})"
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
                              is_allocated: @allocated, asset_group: @group)
    provision.item_count = grant.item_count if counted?
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
