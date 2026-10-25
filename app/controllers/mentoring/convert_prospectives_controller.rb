# frozen_string_literal: true

# Bulk Prospective -> Alpha conversion for the Mentors (Ember
# mentor/convert-prospectives, backed by MentorController::eligibleAlphas and
# ::convertProspectives).
#
# The roster is every Prospective who passed a training session this year. Rows
# carry the shared pipeline chips and expand into the same lazily-loaded intake
# history the other flagging pages show, because reading someone's ranks and
# notes before making them an Alpha is the point of the page. That history is
# rendered here rather than linked to /person/:id/unified-flagging on purpose:
# that page needs the Intake or Regional Management role, which a plain Mentor
# -- this page's own audience -- does not have.
class Mentoring::ConvertProspectivesController < ApplicationController
  include UnifiedFlaggingConcern

  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to convert Prospectives."

  def index
    @converted = []
    @skipped_count = 0
    load_roster
  end

  # Renders the roster again instead of redirecting: a GET cannot re-derive who
  # was just converted -- they are Alphas now, and so off the roster the page is
  # built from -- and Turbo drops a 200 form response. The house 422 results
  # pattern, with the just-converted people held on the page one last time.
  def convert
    ids = IdList.parse(params.permit(person_ids: [])[:person_ids])

    if ids.empty?
      return redirect_to mentoring_convert_prospectives_path,
                         alert: "Select at least one Prospective to convert."
    end

    @converted = ProspectiveConversion.convert(ids, @year)
    @skipped_count = ids.size - @converted.size
    load_roster

    render :index, status: :unprocessable_entity
  end

  private

  # Pinned, not read from params, for the same reason as the sibling page: the
  # roster is who holds Prospective status right now, so honouring ?year= would
  # list today's Prospectives against a past year's training and notes.
  def setup_year
    @year = Current.year
  end

  # @converted is already set by the time this runs, so the just-converted
  # people are both held on the page and left out of the two figures, which
  # describe who is still convertible.
  def load_roster
    @converted_ids = @converted.map(&:id).to_set
    @summaries = Intake.retrieve_trained_prospectives(@year, keep_ids: @converted_ids.to_a)

    remaining = @summaries.reject { |summary| @converted_ids.include?(summary[:person].id) }
    @eligible_count = remaining.size
    @personnel_flag_count = remaining.count { |summary| summary[:personnel_issue] }
  end

  # This page has no year to carry, so the shared row's year: is dropped rather
  # than trailing a meaningless ?year= through every frame URL.
  def unified_flagging_detail_path(person, **_params)
    mentoring_convert_prospectives_detail_path(person)
  end

  # Writable: a mentor sizing someone up here often has a note to leave. Which
  # teams they may actually write for is decided by
  # Person::IntakeNotesController::PERMISSION_ROLE_FOR_TYPE -- a Mentor gets the
  # Mentor team only, upstream's mentorNotesOnly reached through the role map.
  def unified_flagging_read_only?
    false
  end

  def unified_flagging_origin
    { origin: "mentoring_convert" }
  end
end
