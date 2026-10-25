# frozen_string_literal: true

# The Shift Lead Report: who is covering a shift period, as Khaki reads it.
#
# Two flavours of one page. Picking a shift from the list reports its sign-ups;
# the On Duty button reports whoever is signed in right now. Nothing loads until
# one of the two is asked for -- upstream does the same, and the page is opened
# on playa bandwidth over a roster of hundreds.
#
# Upstream: Ember reports/shift-lead, over slot/dirt-shift-times,
# slot/shift-lead-report and timesheet/on-duty-shift-lead-report.
class Scheduling::ShiftLeadController < ApplicationController
  layout "scheduling"

  before_action :setup_year

  # Upstream gates all three endpoints behind Event Management alone; the Ember
  # menu adds Admin. The report reads gender, pronouns, camp vehicle standing
  # and certifications for a whole shift, so the gate is not widened here.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Event Management role required to read the Shift Lead Report."

  # Upstream's YearSelect starts at 2010.
  self.year_floor = 2010

  ON_DUTY_MODE = "on-duty"

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # The narrowing filters, in the order the panel offers them. The sorts are not
  # here: they re-order a roster rather than narrow it, and each belongs to one.
  FILTER_KEYS = [:years, :position, :gender, :vehicle, :start_time].freeze

  def index
    load_page
  end

  # The same report as a paper document: no picker, no folds, no links, and the
  # chrome-free print layout. `render layout:` inside the action rather than a
  # class-level `layout "print", only: :print_sheet` -- that form REPLACES the
  # inherited "scheduling" layout for every other action rather than adding to
  # it, which would cost `index` its sidebar.
  def print_sheet
    load_page
    # Nothing was asked for, so there is nothing to put on paper.
    return redirect_to scheduling_shift_lead_path(year: @year) unless @report

    render layout: "print"
  end

  private

  # Both actions answer the same question and read the same query string; only
  # the rendering differs.
  def load_page
    @shifts = Slot.retrieve_dirt_times(@year)
    @on_duty_mode = (params[:mode] == ON_DUTY_MODE)
    @slot = selected_slot unless @on_duty_mode

    @report = load_report
    return unless @report

    @filter_params = filter_params
    @dirt = visible_rangers(@report.dirt, @filter_params[:sort_dirt])
    @command = visible_rangers(@report.command, @filter_params[:sort_command])
    @special = visible_rangers(@report.special, @filter_params[:sort_special])
    @shown_count = @dirt.size + @command.size + @special.size
    @total_count = every_ranger.size
    @filter_options = FILTER_KEYS.index_with { |key| filter_options_for(key) }
  end

  def every_ranger = @every_ranger ||= @report.dirt + @report.command + @report.special

  # Each filter is validated against the values the report actually holds
  # rather than a fixed vocabulary. A stale bookmark naming a position no one is
  # standing this shift would otherwise empty every roster while its chip
  # claimed to be narrowing something.
  def filter_params
    helper = Scheduling::ShiftLeadHelper
    rangers = every_ranger

    {
      years: known(params[:years], helper::YEARS_LABELS.keys),
      position: known(params[:position], rangers.map(&:position_full_title).uniq),
      gender: known(params[:gender], rangers.filter_map { |r| r.gender.presence }.uniq),
      vehicle: known(params[:vehicle], helper::VEHICLE_LABELS.keys),
      # There is no sign-up to have a start time on the live report, so the
      # filter is forced off there rather than silently emptying every roster.
      start_time: @on_duty_mode ? ALL : known(params[:start_time], rangers.filter_map { |r| start_time_of(r) }.uniq),
      **helper::ROSTER_SECTIONS.to_h { |section|
        [:"sort_#{section}", known_sort(params[:"sort_#{section}"])]
      }
    }
  end

  def known(value, allowed) = UiComponents::FilterBarHelper.known_filter(value, allowed)

  # Sorts do not take the filter bar's "all" sentinel: a roster is always
  # ordered somehow, and an unrecognised value means the report's own order
  # rather than no order at all.
  def known_sort(value)
    labels = Scheduling::ShiftLeadHelper::SORT_LABELS

    labels.key?(value) ? value : Scheduling::ShiftLeadHelper::SORT_DEFAULT
  end

  # The options each select offers.
  #
  # Built from the rangers that pass every OTHER filter, so a count promises the
  # roster the choice actually delivers, and an option that could only return an
  # empty roster is not offered at all. Counting against the whole report instead
  # advertises "F (12)" while the years filter in force leaves none of them.
  #
  # The value in force is kept even at zero: a select cannot show a choice that
  # is not among its options, and dropping it would silently redraw the control
  # as "All" while the chip beside it still said otherwise.
  def filter_options_for(key)
    pool = filter_rangers(every_ranger, @filter_params.except(key))
    options = [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + counted_options(key, pool)
    chosen = @filter_params[key]
    return options if chosen == ALL || options.any? { |_label, value| value == chosen }

    options + [["#{filter_option_label(key, chosen)} (0)", chosen]]
  end

  def counted_options(key, pool)
    helper = Scheduling::ShiftLeadHelper

    case key
    when :years
      # A floor rather than a value, so these count by comparison rather than by
      # tally -- every Ranger falls in every bucket at or below their own.
      helper::YEARS_LABELS.filter_map { |floor, label|
        count = pool.count { |ranger| ranger.years.to_i >= floor.to_i }
        ["#{label} (#{count})", floor] if count.positive?
      }
    when :vehicle
      helper::VEHICLE_LABELS.filter_map { |token, label|
        count = pool.count { |ranger| vehicle_match?(ranger, token) }
        ["#{label} (#{count})", token] if count.positive?
      }
    when :position
      # Full titles, not the roster column's abbreviations: a select is where the
      # reader chooses rather than reads, and "Green Dot Lead" needs no decoder
      # ring. Alphabetical -- they come to it with a position already in mind.
      tallied_options(pool.map(&:position_full_title)) { |title| title.downcase }
    when :gender
      # Blank genders are left out: "has not said" is not a roster anyone staffs
      # from, and the dash would read as a code of its own.
      tallied_options(pool.filter_map { |ranger| ranger.gender.presence })
    when :start_time
      tallied_options(pool.filter_map { |ranger| start_time_of(ranger) })
    end
  end

  def tallied_options(values, &sort_key)
    sort_key ||= :itself.to_proc

    values.tally.sort_by { |value, _count| sort_key.call(value) }
          .map { |value, count| ["#{value} (#{count})", value] }
  end

  def filter_option_label(key, value)
    helper = Scheduling::ShiftLeadHelper

    case key
    when :years then helper::YEARS_LABELS.fetch(value, value)
    when :vehicle then helper::VEHICLE_LABELS.fetch(value, value)
    else value
    end
  end

  # Both flavours of the report arrive fully materialised and already sorted, so
  # narrowing and re-ordering them is array work rather than another query.
  def visible_rangers(rangers, sort_key) = sort_rangers(filter_rangers(rangers, @filter_params), sort_key)

  # `fetch(key, ALL)` rather than `[key]`: filter_options_for hands this the
  # filters with one key dropped, and a key that is simply absent means "not
  # narrowing on that" -- reading it as nil would compare against nil instead.
  def filter_rangers(rangers, filters)
    years = filters.fetch(:years, ALL)
    position = filters.fetch(:position, ALL)
    gender = filters.fetch(:gender, ALL)
    vehicle = filters.fetch(:vehicle, ALL)
    start_time = filters.fetch(:start_time, ALL)

    rangers.select do |ranger|
      (years == ALL || ranger.years.to_i >= years.to_i) &&
        (position == ALL || ranger.position_full_title == position) &&
        (gender == ALL || ranger.gender == gender) &&
        (vehicle == ALL || vehicle_match?(ranger, vehicle)) &&
        (start_time == ALL || start_time_of(ranger) == start_time)
    end
  end

  # One control for both vehicle columns: they answer the single question of
  # whether this Ranger may take a rig out. Blacklisted is set on both, so
  # either one answers for it.
  def vehicle_match?(ranger, choice)
    helper = Scheduling::ShiftLeadHelper

    case choice
    when helper::VEHICLE_GTR then ranger.gtr == :yes
    when helper::VEHICLE_VEH then ranger.vehicle == :yes
    when helper::VEHICLE_BOTH then ranger.gtr == :yes && ranger.vehicle == :yes
    when helper::VEHICLE_BLACKLISTED then ranger.gtr == :blacklisted
    else true
    end
  end

  # Ruby's sort_by is not stable, so every sort has to end on a key that cannot
  # tie. Callsign is not that key: a roster carries one row per sign-up and
  # never dedupes by person, and DIRT_AND_GREEN_DOT_POSITIONS puts Dirt and
  # Green Dot slots on one roster -- so a Ranger standing both appears twice
  # with the same callsign, the same gender and the same years, tying every
  # other key too. Position and start time separate those two rows.
  def sort_rangers(rangers, sort_key)
    helper = Scheduling::ShiftLeadHelper

    case sort_key
    when helper::SORT_GENDER
      # Blank genders last rather than first: an unstated gender is the absence
      # of the thing being sorted on, not the lowest value of it.
      rangers.sort_by { |r| [r.gender.blank? ? 1 : 0, r.gender.to_s, *tiebreak(r)] }
    when helper::SORT_YEARS then rangers.sort_by { |r| [-r.years.to_i, *tiebreak(r)] }
    when helper::SORT_CALLSIGN then rangers.sort_by { |r| tiebreak(r) }
    else rangers # the report's own order, which upstream defines
    end
  end

  # `begins` on the scheduled report, `on_duty` on the live one -- a row carries
  # one or the other, never both, and 0 stands in for neither.
  def tiebreak(ranger)
    [ranger.callsign.downcase, ranger.position_title.to_s,
     (ranger.begins || ranger.on_duty)&.to_i || 0]
  end

  def start_time_of(ranger) = ranger.begins&.strftime(DateTimeHelper::HOUR_MINS)

  # Nothing is asked for until the reader picks a shift or asks for the live
  # report -- the first view is the picker alone.
  def load_report
    return OnDutyShiftLeadReport.execute if @on_duty_mode
    return unless @slot

    ShiftLeadReport.execute(shift_start: @slot.begins, shift_duration: @slot.duration)
  end

  # The shift picked from the list.
  #
  # Resolved against the year's dirt shifts rather than trusted from the query
  # string. Upstream posts the window itself -- a start time and a duration --
  # which lets any caller ask for a report over any window at all; here the only
  # windows that can be asked about are the ones the picker offers.
  # `to_i` rather than the raw parameter, because ?slot_id[]=1 hands us an Array
  # and ?slot_id[a]=1 an ActionController::Parameters, neither of which is blank
  # and neither of which answers to_i.
  def selected_slot
    slot_id = params[:slot_id]
    return unless slot_id.is_a?(String) && slot_id.present?

    shift = @shifts.find { |dirt_shift| dirt_shift.id == slot_id.to_i }
    Slot.find_by(id: shift.id) if shift
  end
end
