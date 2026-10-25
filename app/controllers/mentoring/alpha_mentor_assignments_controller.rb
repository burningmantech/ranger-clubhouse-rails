# frozen_string_literal: true

# The Alpha Mentor Assignments worksheet (upstream Ember mentor/assignment off
# MentorController::{alphas,mentors,mentorAssignment}). One filtered table of
# every current Alpha, three mentor selects and a result per row, saved in one
# transaction.
#
# Deliberate departures from upstream, settled when this page was specced
# (see .scratch/mentoring-alpha-mentor-assignments/PLAN.md):
#
#   * Filtering is server-side, and the pod fill is a toolbar select rather
#     than a modal, so neither depends on browser state that a reload loses.
#   * Every validation upstream does in the browser is done here instead:
#     duplicate mentors, a verdict with no one attached, and a mentor who does
#     not hold the position. Upstream's checks are advisory at best -- its
#     duplicate test compares a String select value against an Integer.
#   * The whole sheet is written in ONE transaction. Upstream gives each Alpha
#     its own, so an interruption leaves half a sheet recorded.
#   * A save only touches the rows on screen. Upstream posts every Alpha
#     regardless of the filter, which means a filtered view still rewrites
#     rows the reader cannot see.
class Mentoring::AlphaMentorAssignmentsController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to record mentor assignments."

  ALL_FILTER = AlphaMentorAssignment::ALL_FILTER

  def index
    load_worksheet
  end

  # Record the sheet. A clean save redirects back to the same filtered view
  # (post/redirect/get); anything else re-renders the worksheet at 422, because
  # Turbo silently drops a 200 response to a form submission.
  def save
    rows = submitted_rows.values

    if rows.empty?
      return redirect_to(mentoring_alpha_mentor_assignments_path(filter_params),
                         alert: "No Alphas were listed, so there was nothing to record.")
    end

    # Upstream's "No Bonks?" prompt, as a server-side second step: the first
    # submit comes back with the question, the button on it carries `confirmed`.
    if params[:confirmed].blank? && AlphaMentorAssignment.needs_bonk_confirmation?(rows)
      @passed_count = rows.count { |row| row.mentor_ids.any? && row.status == PersonMentor::STATUS_PASS }
      return rerender(rows, confirm_bonks: true)
    end

    @result = AlphaMentorAssignment.assign!(@year, rows)
    return rerender(rows) unless @result.ok?

    redirect_to mentoring_alpha_mentor_assignments_path(filter_params), success: saved_message(@result)
  end

  # Fill blank mentor slots from a shift's pods. Writes nothing: the worksheet
  # comes back with the values in place so they can be read before saving.
  def pod_prefill
    slot = alpha_slots.find { |candidate| candidate.id == params[:pod_slot_id].to_i }

    unless slot
      return redirect_to(mentoring_alpha_mentor_assignments_path(filter_params),
                         alert: "Pick one of this year's Alpha shifts to fill mentors from.")
    end

    rows = submitted_rows
    # The fill's redraw would show a malformed row as only the ids it kept.
    if rows.each_value.any?(&:mentors_malformed)
      return redirect_to(mentoring_alpha_mentor_assignments_path(filter_params),
                         alert: "The mentors were not submitted correctly, so nothing was filled in. Try again.")
    end

    @prefill = AlphaMentorAssignment.pod_prefill(slot, rows)
    @prefill_slot = slot
    rerender(@prefill.rows.values)
  end

  def print_sheet
    load_worksheet
    @back_params = filter_params
    render layout: "print"
  end

  private

  # Pinned, not read from params: the roster is who holds Alpha status right
  # now, so honouring ?year= would list today's Alphas against a past year's
  # shifts and mentors. Matches the four other current-standing Mentoring pages.
  def setup_year
    @year = Current.year
  end

  # Both values are coerced to a String and checked against what the filter bar
  # actually offers. `?shift[]=x` would otherwise put an Array into a chip
  # label and into path generation -- and on the save path that lands AFTER the
  # rows are committed, so the sheet would be recorded and the operator would
  # see only a 500.
  STATUS_FILTERS = [
    AlphaMentorAssignment::ALL_FILTER,
    AlphaMentorAssignment::STATUS_PENDING_WITH_MENTORS,
    AlphaMentorAssignment::STATUS_PASSED,
    AlphaMentorAssignment::STATUS_BONKED
  ].freeze

  SHIFT_FILTERS = [
    AlphaMentorAssignment::ALL_FILTER,
    AlphaMentorAssignment::SHIFT_NOT_CHECKED_IN,
    AlphaMentorAssignment::SHIFT_CHECKED_IN
  ].freeze

  SHIFT_SLOT_FILTER = /\A(#{AlphaMentorAssignment::CHECKED_IN_PREFIX}|
                         #{AlphaMentorAssignment::SIGNED_UP_PREFIX})\d+\z/x

  def filter_params
    { status: filter_value(params[:status], STATUS_FILTERS),
      shift: filter_value(params[:shift], SHIFT_FILTERS, SHIFT_SLOT_FILTER) }
  end

  def filter_value(raw, allowed, pattern = nil)
    value = raw.is_a?(String) ? raw : ""
    return value if allowed.include?(value)
    return value if pattern&.match?(value)

    AlphaMentorAssignment::ALL_FILTER
  end

  # `pending_edits` lets a 422 re-render show what was typed rather than what is
  # stored -- otherwise a reader fixing one duplicate would lose every other
  # edit on the sheet.
  def load_worksheet(pending_edits: nil)
    @roster = AlphaMentorAssignment.roster(@year)
    @filter_params = filter_params
    @entries = apply_filters(@roster)
    @pending_edits = pending_edits

    @total = @roster.size
    @pending_count = @roster.count(&:pending?)
    @passed_total = @roster.count(&:passed?)
    @bonked_total = @roster.count(&:bonked?)
    @checked_in_count = @roster.count(&:checked_in?)
    @walking_unknown = @roster.select(&:walking_unknown?)

    @alpha_slots = alpha_slots
    @mentor_pool = AlphaMentorAssignment.mentor_pool(@year)
    @former_mentors = AlphaMentorAssignment.former_mentors(@entries, @mentor_pool)
    # Only shifts that actually have pods can be filled from, so the toolbar
    # needs the counts to decide what to offer.
    @pod_counts = Pod.where(slot_id: @alpha_slots.map(&:id), type: Pod::TYPE_MENTOR)
                     .group(:slot_id).count
  end

  def rerender(rows, confirm_bonks: false)
    @confirm_bonks = confirm_bonks
    load_worksheet(pending_edits: rows.index_by(&:person_id))
    render :index, status: :unprocessable_entity
  end

  def alpha_slots
    @alpha_slots ||= AlphaMentorAssignment.alpha_slots_for_year(@year)
  end

  # The worksheet arrives as `alphas[<person_id>][status]` plus a repeated
  # `alphas[<person_id>][mentor_ids][]`, the keyed-hash shape every other
  # many-row form in this app uses. Both guards are deliberate: the hash comes
  # off the wire and a hand-typed URL can make either half the wrong type.
  def submitted_rows
    rows = params[:alphas]
    return {} unless rows.respond_to?(:each_pair)

    rows.each_pair.filter_map do |person_id, attributes|
      next unless attributes.respond_to?(:permit)

      values = attributes.permit(:status, mentor_ids: [])
      id = person_id.to_i
      next unless id.positive?

      [id, AlphaMentorAssignment::Row.new(
        person_id: id,
        status: values[:status].to_s,
        # One at a time rather than IdList.parse, which drops repeats: the same
        # mentor picked twice is an error the reader needs to see.
        mentor_ids: Array(values[:mentor_ids]).filter_map { |value| IdList.id(value) },
        mentors_malformed: !IdList.clean?(values[:mentor_ids])
      )]
    end.to_h
  end

  def saved_message(result)
    return "Nothing had changed, so nothing was recorded." if result.changed_count.zero?

    parts = []
    parts << "Recorded #{helpers.pluralize(result.saved_count, "Alpha")}" if result.saved_count.positive?
    parts << "cleared #{helpers.pluralize(result.cleared_count, "Alpha")}" if result.cleared_count.positive?
    "#{parts.to_sentence.upcase_first}."
  end

  def apply_filters(entries)
    entries = filter_by_status(entries, @filter_params[:status])
    filter_by_shift(entries, @filter_params[:shift])
  end

  # Upstream's "Pending w/Mentor assignment" means pending AND at least one
  # mentor picked -- the sheet is half-done, not untouched. Its "Bonked" filter
  # tests the string "bonked", which is not a status any more than "passeded"
  # is, so it silently matches self-bonks only; both are matched here.
  def filter_by_status(entries, status)
    case status
    when AlphaMentorAssignment::STATUS_PENDING_WITH_MENTORS
      entries.select { |entry| entry.pending? && entry.mentors.any? }
    when AlphaMentorAssignment::STATUS_PASSED then entries.select(&:passed?)
    when AlphaMentorAssignment::STATUS_BONKED then entries.select(&:bonked?)
    else entries
    end
  end

  def filter_by_shift(entries, shift)
    case shift
    when AlphaMentorAssignment::SHIFT_NOT_CHECKED_IN then entries.reject(&:checked_in?)
    when AlphaMentorAssignment::SHIFT_CHECKED_IN then entries.select(&:checked_in?)
    when /\A#{AlphaMentorAssignment::CHECKED_IN_PREFIX}(\d+)\z/o
      slot_id = ::Regexp.last_match(1).to_i
      entries.select { |entry| entry.shift_slot&.id == slot_id }
    when /\A#{AlphaMentorAssignment::SIGNED_UP_PREFIX}(\d+)\z/o
      slot_id = ::Regexp.last_match(1).to_i
      entries.select { |entry| entry.alpha_slots.any? { |slot| slot.id == slot_id } }
    else entries
    end
  end
end
