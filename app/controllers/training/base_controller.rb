# frozen_string_literal: true

# Shared shell for the per-position training interface (Ember
# training/:position_id tree). Resolves the training position from the URL and
# enforces the Laravel TrainingPolicy view rule -- the Ember client guard was
# looser and is NOT the authority: admins always pass, ART trainings need the
# position's composed ART interface role, and In-Person Training takes
# Trainer, Mentor, or VC.
class Training::BaseController < ApplicationController
  layout "training"

  before_action :load_training
  before_action :authorize_training_view
  before_action :setup_year

  helper_method :can_manage_session?, :can_adjust_roster?, :can_graduate?, :training_slug

  private

  # The resolved position's URL slug -- every training path helper takes it
  # as the first segment.
  def training_slug
    @training_slug ||= Training.slug(@training)
  end

  # The URL carries a title slug ("in-person", "green-dot") and only
  # training-type non-trainer positions can match one, which closes
  # upstream's unvalidated route-binding hole where any position id would
  # load. Inactive trainings resolve on purpose -- menus list active
  # positions only, but direct URLs to inactive ones still reach their
  # historical data. An unknown slug gets the house friendly redirect
  # (vc/applications, me/surveys precedent), not a bare 404.
  def load_training
    @training = Training.find_training_position(params[:slug])
  rescue Training::NotTrainingPositionError
    redirect_to me_root_path, error: "Training position not found."
  end

  # authorize_role only takes a static list, so the URL-derived composed-role
  # check lives here instead. The same list drives the menu category's
  # visible_if (TrainingMenu), so what the menu shows and what the
  # controller admits cannot drift.
  def authorize_training_view
    return if has_role?(Training.view_roles(@training))

    not_authorized_redirect("You are not authorized to view the #{@training.title} interface.")
  end

  # The session slot must belong to this training (HQ Full Training also
  # manages the refresher slots -- Training.session_position_ids is the
  # authority). A stray slot id gets the friendly redirect to the landing.
  def load_session
    slot = Slot.where(position_id: Training.session_position_ids(@training.id))
               .find_by(id: params[:slot_id])

    unless slot
      redirect_to training_path(Training.slug(@training)), error: "Training session not found."
      return
    end

    @training_session = TrainingSession.new(slot, @training)
  end

  # Training links are built per position at request time, so the static
  # MegaMenu.tracked_paths never holds them. @training is always loaded here:
  # a halted before_action skips the after_action that calls this. Exact path
  # match -- session pages and CSV exports are not menu links.
  def tracked_page?
    super || MegaMenu.linkable_items([TrainingMenu.definition(@training)]).key?(request.path)
  end

  # --- session abilities (TrainingSessionPolicy port; admin always passes) --

  # Score trainees, save trainer attendance, edit notes. Dirt MENTOR/VC are
  # view-only; ART management is the same composed role as viewing.
  def can_manage_session?
    if Training.art?(@training)
      has_role?([Role::ADMIN, Role::ART_TRAINER_BASE | @training.id])
    else
      has_role?([Role::ADMIN, Role::TRAINER])
    end
  end

  # Add/remove people. Dirt requires admin or the DIRECTLY assigned Trainer
  # role -- a Trainer Seasonal masquerade may not adjust rosters (Training
  # Academy 2023 rule); ARTs take any of their trainers.
  def can_adjust_roster?
    return true if has_role?(Role::ADMIN)

    if Training.art?(@training)
      has_role?(Role::ART_TRAINER_BASE | @training.id)
    else
      Current.roles_manager&.has_directly_assigned_role?(Role::TRAINER) || false
    end
  end

  # Graduate trainees into the ART's positions (ART-only ability).
  def can_graduate?
    Training.art?(@training) && has_role?([Role::ADMIN, Role::ART_GRADUATE_BASE | @training.id])
  end

  def authorize_session_management
    return if can_manage_session?

    not_authorized_redirect("You are not authorized to manage #{@training.title} sessions.")
  end

  def authorize_roster_adjustment
    return if can_adjust_roster?

    not_authorized_redirect("You are not authorized to adjust the session roster.")
  end

  def authorize_graduation
    return if can_graduate?

    not_authorized_redirect("You are not authorized to graduate trainees.")
  end
end
