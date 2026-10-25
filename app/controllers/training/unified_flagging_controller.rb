# frozen_string_literal: true

# In-Person Training's read-only view of the applicant pipeline (Ember
# training/:position_id/unified-flagging). Upstream rendered the very same
# <UnifiedFlagging> component off the very same position-agnostic `intake`
# endpoint as the /vc route -- the only difference was trainingNotesOnly, which
# made every intake team's notes read-only. UnifiedFlaggingConcern carries the
# page; this class supplies the URLs and says no to writing.
#
# Two gates, both required, matching upstream's pairing of the training tree's
# route guard with this child route's roleRequired = INTAKE:
#   * Training::BaseController's authorize_training_view -- Trainer/Mentor/VC
#   * authorize_role Training.unified_flagging_roles -- Admin or Intake
# authorize_role writes a class attribute consumed by ApplicationController's
# gatekeeper rather than registering a callback, so it stacks with the
# inherited before_action instead of replacing it (and the base sets no
# authorized_roles of its own to clobber).
class Training::UnifiedFlaggingController < Training::BaseController
  include UnifiedFlaggingConcern

  # Upstream's YearSelect on this route starts at 2008, two years earlier than
  # the /vc copy's 2010. Also the selector's first year, so ?year= cannot name
  # a year the selector does not offer.
  self.year_floor = 2008

  before_action :require_in_person_training

  authorize_role Training.unified_flagging_roles,
                 message: "Admin or Intake role required to view unified flagging."

  private

  # Intake data is not position-scoped -- Intake.retrieve_all_for_year takes no
  # position, and history_for_person reads In-Person Training sessions
  # specifically. Under an ART slug the page would render the identical global
  # roster with In-Person training history beside an ART's name, so the ARTs
  # do not get a copy. Upstream reached the same place from the other side: its
  # sidebar linked this page only from the non-ART branch.
  def require_in_person_training
    return if @training.id == Position::TRAINING

    redirect_to training_path(training_slug),
                error: "Unified Flagging covers the whole applicant pipeline and lives under In-Person Training."
  end

  def unified_flagging_path(**params)
    training_unified_flagging_path(training_slug, **params)
  end

  def unified_flagging_detail_path(person, **params)
    training_unified_flagging_detail_path(training_slug, person, **params)
  end

  # trainingNotesOnly. Trainers read the pipeline here; notes are filed from
  # the /vc page or the person page, which is also why no origin token is
  # needed -- nothing on this page opens a note form.
  def unified_flagging_read_only?
    true
  end

  def unified_flagging_origin
    {}
  end
end
