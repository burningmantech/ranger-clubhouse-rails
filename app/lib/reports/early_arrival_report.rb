# frozen_string_literal: true

# Everyone arriving before the Thursday leading into gate opening weekend, so
# their arrival packets can be put together ahead of time.
#
# Somebody is listed for either of two reasons: their pass lets them onto playa
# before that Thursday, or they hold a shift in the days leading up to it. The
# two answers are gathered separately and then merged, because plenty of people
# are only one or the other -- a pass with no shift yet, or a shift booked by
# somebody whose pass has not been issued.
#
# The window is worked out from the year's event start rather than read from a
# stored date. The stored pre-event date covers the whole run up to the event
# and is far too early to pick arrivals out of.
#
# Only the event now being prepared can answer the whole question. Passes,
# radio allowances, and the on-playa flag are all live: they say what is true
# today and keep no history, so reading them against an earlier year would put
# today's pass holders on a report from years ago. An earlier year is therefore
# built from what was written down at the time -- the shifts people held, their
# badges, their agreements, and the radios they actually drew -- and says so.
class EarlyArrivalReport
  # How many days before the cutoff the shift window opens.
  WINDOW_DAYS = 5

  # One radio somebody is holding. An event radio is theirs for the whole event;
  # anything else was handed out for a single shift.
  Radio = Struct.new(:barcode, :event_radio) do
    def label = event_radio ? "event" : "shift"
  end

  # The first shift somebody stands inside the window.
  Shift = Struct.new(:position_title, :begins, :description)

  # One person and everything a packet needs for them.
  #
  # `sap_date` says when they may arrive and reads three ways: `:any` for a pass
  # good at any time, a Date for a pass tied to one, and nil when no pass is on
  # file yet.
  # `live` marks a row from the event now being prepared. On an earlier year it
  # is false, and the fields that keep no history -- the pass, the radio
  # allowance, whether the person is on playa -- are left empty rather than
  # answered with today's values.
  Row = Struct.new(:person, :sap_date, :bmid_status, :first_shift,
                   :radio_agreement, :radios_allowed, :radios, :live) do
    def person_id = person.id
    def callsign = person.callsign

    # Nothing recorded whether somebody was on playa during an earlier event, so
    # an earlier year answers "not known" rather than repeating today's flag.
    def on_site = live ? person.on_site : nil

    def any_time? = sap_date == :any
    def dated? = sap_date.is_a?(Date)
    def no_sap? = sap_date.nil?
    def shift? = !first_shift.nil?

    # Which day this person turns up, for grouping and filtering. A pass good at
    # any time has no one day, and neither has somebody with no pass at all.
    def arrival_date = dated? ? sap_date : nil

    def shift_date = first_shift&.begins&.to_date
  end

  # The whole report. Every figure the page prints is counted here in one walk
  # of the list, so the boxes above the table and the table itself cannot
  # disagree about what was found.
  Result = Struct.new(:status, :rows, :pre_event_start, :pre_event_end, :live) do
    def no_event_dates? = status == :no_event_dates
    def none? = rows.empty?

    # True for the event now being prepared. The page asks this before showing
    # anything read from live records, and says why when it cannot.
    def live? = live

    def total = counts[:total]
    def any_time_count = counts[:any_time]
    def no_sap_count = counts[:no_sap]
    def no_shift_count = counts[:no_shift]
    def unsigned_count = counts[:unsigned]
    def on_site_count = counts[:on_site]

    # The days people actually arrive on, for the arrival filter. Only days
    # somebody is listed under are offered: a choice that can only come back
    # empty is not worth putting on screen. Both lists are settled once -- the
    # page and the filter that validates it each ask for them.
    def arrival_dates = @arrival_dates ||= rows.filter_map(&:arrival_date).uniq.sort

    def shift_dates = @shift_dates ||= rows.filter_map(&:shift_date).uniq.sort

    # The filters worth offering. A year with no pass data behind it cannot
    # answer the three that read one, so the page does not put them up.
    def arrival_date_keys = arrival_dates.map(&:to_s)

    def shift_date_keys = shift_dates.map(&:to_s)

    private

    def counts
      @counts ||= rows.each_with_object(Hash.new(0)) { |row, tally|
        tally[:total] += 1
        tally[:any_time] += 1 if row.any_time?
        tally[:no_sap] += 1 if row.no_sap?
        tally[:no_shift] += 1 unless row.shift?
        tally[:unsigned] += 1 unless row.radio_agreement
        tally[:on_site] += 1 if row.on_site
      }
    end
  end

  class << self
    # The whole report for one year, in callsign order.
    def build(year:)
      event_date = EventDate.find_for_year(year)
      return Result.new(:no_event_dates, [], nil, nil, false) unless event_date

      cutoff = event_date.event_start.to_date.prev_occurring(:thursday)
      opens = cutoff - WINDOW_DAYS
      live = (year == Current.year)

      # Passes keep no history, so only the event being prepared can be asked
      # who holds one. An earlier year is built from its shifts alone.
      saps = live ? AccessDocument.retrieve_saps_prior_to(cutoff).index_by(&:person_id) : {}
      shifts = first_shifts(year:, opens:, cutoff:)

      person_ids = (saps.keys + shifts.keys).uniq
      return Result.new(:no_arrivals, [], opens, cutoff, live) if person_ids.empty?

      rows = rows_for(year:, person_ids:, saps:, shifts:, live:)
      Result.new(:ok, rows, opens, cutoff, live)
    end

    private

    # The first shift each person stands inside the window, keyed by person.
    #
    # Training does not count: sitting a class is not turning up to build the
    # city, and a trainee has no packet waiting for them.
    #
    # Training positions are named and then excluded, rather than asking each
    # position whether its type differs from Training. A position with no type
    # set at all answers neither yes nor no to that question, and the database
    # settles the tie by dropping the row -- which would quietly lose somebody
    # who is genuinely arriving early.
    def first_shifts(year:, opens:, cutoff:)
      training = Position.where(type: Position::TYPE_TRAINING)

      PersonSlot.joins(slot: :position)
                .where(slot: { begins_year: year, begins: opens..cutoff })
                .where.not(slot: { position_id: training })
                .order("slot.begins")
                .pluck(:person_id, "position.title", "slot.begins", "slot.description")
                .each_with_object({}) { |(person_id, title, begins, description), first|
                  # Ordered by start time, so the first one seen is the earliest
                  # and later ones for the same person are passed over.
                  first[person_id] ||= Shift.new(title, begins.in_time_zone, description)
                }
    end

    def rows_for(year:, person_ids:, saps:, shifts:, live:)
      # Only the columns the page draws, plus status, which any roster is one
      # edit away from wanting. Reading a column left out of a select raises
      # rather than returning a value, so the four are named together here.
      people = Person.where(id: person_ids)
                     .select(:id, :callsign, :on_site, :status).index_by(&:id)
      bmids = Bmid.where(year:, person_id: person_ids).pluck(:person_id, :status).to_h
      allowed = live ? radios_allowed(person_ids) : {}
      issued = radios_issued(year:, person_ids:)
      signed = PersonEvent.where(year:, person_id: person_ids, asset_authorized: true)
                          .pluck(:person_id).to_set

      person_ids.filter_map { |person_id|
        person = people[person_id]
        next unless person

        Row.new(person, sap_date_for(saps[person_id]), bmids[person_id],
                shifts[person_id], signed.include?(person_id),
                allowed[person_id].to_i, issued[person_id] || [], live)
      }.sort_by { |row|
        # person_id breaks ties so two people sharing a callsign keep a stable
        # order -- sort_by is not stable on its own, and the page and its export
        # have to list them the same way round.
        [row.callsign.downcase, row.person_id]
      }
    end

    # A pass good at any time outranks a dated one, and no pass at all reads as
    # nothing rather than as a date the page would have to invent.
    def sap_date_for(sap)
      return nil unless sap
      return :any if sap.access_any_time

      sap.access_date&.to_date
    end

    # How many radios each person may draw. Somebody can hold more than one
    # entitlement, so the largest is the number that counts.
    #
    # An entitlement with no count on it means one radio, which is what the HQ
    # window hands over. Left as it is stored, the largest of a set of blanks is
    # nothing at all, and the packet would be assembled for a person the window
    # is about to give a radio to.
    def radios_allowed(person_ids)
      Provision.where(person_id: person_ids, type: Provision::EVENT_RADIO,
                      status: Provision::CAN_USE_STATUSES)
               .group(:person_id)
               .maximum(Arel.sql("COALESCE(item_count, 1)"))
    end

    # The radios each person is actually holding, still out and drawn in the
    # report's own year. Barcode order so a packet lists them the same way twice.
    def radios_issued(year:, person_ids:)
      PersonAsset.joins(:asset)
                 .where(person_id: person_ids, checked_in: nil)
                 .where(asset: { type: Asset::TYPE_RADIO })
                 .where_year("checked_out", year)
                 .order("asset.barcode")
                 .pluck(:person_id, "asset.barcode", "asset.perm_assign")
                 .each_with_object({}) { |(person_id, barcode, perm_assign), held|
                   (held[person_id] ||= []) << Radio.new(barcode, perm_assign)
                 }
    end
  end
end
