# frozen_string_literal: true

# End-of-season VC maintenance tasks: bulk callsign and status resets that
# clear out the applicant pipeline. Ported from the Ember /vc/maintenance route
# (port/maintenance-route.js, port/maintenace-controller.js) and the Laravel
# MaintenanceController resetPNVs/resetPassProspectives.
#
# Both tasks walk the roster one person at a time instead of issuing a bulk
# UPDATE: every row needs its own generated callsign, and the operator gets a
# per-person ledger of what actually changed.
#
# The flow is index -> preview -> commit: the index only links to the preview
# pages, each preview page is a full dress rehearsal of its task (same scope,
# same generated callsigns, nothing saved), and the mutating POST lives only on
# the preview page, next to a cancel link back to the index.
#
# Each task renders its ledger on the POST with a 422: the results are transient
# and a GET cannot re-derive them, and Turbo silently drops a 200 form response.
# Matches the reserved handle upload.
class Vc::MaintenanceController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to run maintenance tasks."

  # Everyone still somewhere in this year's applicant pipeline. The waitlist
  # status is deprecated and this schema's status enum cannot even store it, so
  # it matches nothing today; it is kept to stay faithful to upstream, which
  # shares this database and still lists it.
  PNV_STATUSES = [
    Person::ALPHA, Person::BONKED, Person::PROSPECTIVE, Person::PROSPECTIVE_WAITLIST
  ].freeze

  def index
  end

  # GET twins of the two tasks below: same scope, same callsign generation,
  # nothing saved. Each is the full-page review step the operator commits or
  # cancels from.
  def preview_pnvs
    @title = "Reset Applicants to Past Prospective"
    @results = reset_callsigns(pnv_scope, preview: true)
  end

  def preview_past_prospectives
    @title = "Reset Past Prospectives"
    @results = reset_callsigns(past_prospective_scope, preview: true)
  end

  # Revert the applicant pipeline to past prospective, replace each callsign
  # with a generated LastFirstYY handle, and mark it unapproved.
  def reset_pnvs
    @title = "Reset Applicants to Past Prospective"
    @results = reset_callsigns(pnv_scope,
                               reason: "maintenance - pnv reset",
                               new_status: Person::PAST_PROSPECTIVE)
    render :reset_pnvs, status: :unprocessable_entity
  end

  # Past prospectives who held on to an approved callsign get the same
  # generated handle. Their status is already correct, so only the approval
  # flag flips.
  def reset_past_prospectives
    @title = "Reset Past Prospectives"
    @results = reset_callsigns(past_prospective_scope,
                               reason: "maintenance - past prospective reset")
    render :reset_past_prospectives, status: :unprocessable_entity
  end

  private

  # Shared by each task and its preview so the two can never drift apart.
  def pnv_scope
    Person.where(status: PNV_STATUSES)
  end

  def past_prospective_scope
    Person.where(status: Person::PAST_PROSPECTIVE, callsign_approved: true)
  end

  # Returns one result hash per person, ordered by the old callsign.
  # preview: generate the new callsigns but write nothing.
  def reset_callsigns(scope, reason: nil, new_status: nil, preview: false)
    # In a preview nothing is saved, so exists? cannot see collisions inside
    # the batch itself -- track the handles already handed out. (During a real
    # run each save lands before the next lookup, so this never adds anything.)
    taken = Set.new

    scope.order(:callsign).map do |person|
      # Captured before anything moves -- the report is a before/after ledger.
      result = { id: person.id, callsign: person.callsign, status: person.status,
                 callsign_reset: nil, error: nil }

      # reset_callsign has to run while the OLD status is still in place: it
      # appends "B" for bonked and "(NR)" for auditors off the current status,
      # so flipping to past prospective first would silently drop the suffix.
      # It also leaves callsign_changed? true, which is exactly what makes the
      # before_save handle_past_prospective_status callback bail instead of
      # generating a second callsign on top of this one.
      if person.reset_callsign(taken:)
        taken << person.callsign
        unless preview
          person.callsign_approved = false
          person.status = new_status if new_status
          person.audit_reason = reason
          # Mirrors the upstream saveWithoutValidation. Legacy applicant rows
          # routinely fail the modern presence validations on address and phone
          # fields, and a validation failure here would silently skip someone the
          # operator was just told got reset. Callbacks still run, so the
          # person_status row and the past-prospective side effects still happen.
          person.save(validate: false)
        end
        result[:callsign_reset] = person.callsign
      else
        # Ten generated handles were all taken. Nothing was written; the
        # operator sorts this person out by hand.
        result[:error] = "Cannot reset callsign"
      end

      result
    end
  end
end
