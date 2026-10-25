# frozen_string_literal: true

# The VC flavor of the applicant pipeline (Ember /vc/unified-flagging, from
# port/unified-flagging-route.js and port/components/unified-flagging*.js).
# Everything but the URLs, the earliest year, and note-writing lives in
# UnifiedFlaggingConcern, shared with Training::UnifiedFlaggingController.
#
# This is the writable flavor: an Intake/VC coordinator files notes from here,
# and the "vc" origin token sends the note form back to this page afterwards.
class Vc::UnifiedFlaggingController < ApplicationController
  include UnifiedFlaggingConcern

  layout "vc"

  # Upstream's YearSelect on this route starts at 2010. Also the selector's
  # first year, so ?year= cannot name a year the selector does not offer.
  self.year_floor = 2010

  before_action :setup_year

  authorize_role [Role::ADMIN, Role::VC, Role::INTAKE],
                 message: "Admin, Volunteer Coordinator, or Intake role required to view unified flagging."

  private

  def unified_flagging_path(**params)
    vc_unified_flagging_path(**params)
  end

  def unified_flagging_detail_path(person, **params)
    vc_unified_flagging_detail_path(person, **params)
  end

  def unified_flagging_read_only?
    false
  end

  # The whitelisted token (never a URL -- no open redirect) that returns the
  # note form here, plus the page year, kept distinct from the form's own
  # `year` so a note filed while viewing a past year lands in that year rather
  # than silently in the current one.
  def unified_flagging_origin
    { origin: "vc", origin_year: @year }
  end
end
