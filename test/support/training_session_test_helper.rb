# frozen_string_literal: true

# test_helper loads test/support alphabetically, so this file comes first.
require_relative "training_slot_test_helper"

# Shared world for the session management controller tests: the dirt and
# Green Dot trainings with their trainer positions, the standard roles, and
# role-carrying people. Requires AuthenticationTestHelper +
# TimesheetAdminTestHelper + TrainingSlotTestHelper.
module TrainingSessionTestHelper
  include TrainingSlotTestHelper # create_slot, sign_up

  YEAR = 2026

  def setup_training_session_world
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @dirt_trainer_position = Position.create!(id: Position::TRAINER, title: "Trainer",
                                              type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)
    @green_dot_trainer_position = Position.create!(id: Position::GREEN_DOT_TRAINER, title: "Green Dot Trainer",
                                                   type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::TRAINER_SEASONAL, "Trainer Seasonal")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    ensure_role(Role::ART_GRADUATE_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Graduate")

    @admin = person(:active_ranger)
    @dirt_trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @mentor = person(:inactive_ranger)

    grant_role(@admin, Role::ADMIN)
    grant_role(@dirt_trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
    grant_role(@mentor, Role::MENTOR)

    @dirt_slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 8, 9, 0, 0),
                             description: "Bright Eyes")
    @art_slot = create_slot(@green_dot, begins: Time.zone.local(YEAR, 8, 9, 9, 0, 0),
                            description: "Deep Playa")
  end

  def teardown_training_session_world
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def dirt_session_path(*segments, **params)
    ["/training/in-person/session/#{@dirt_slot.id}", *segments].join("/") +
      (params.any? ? "?#{params.to_query}" : "")
  end

  def art_session_path(*segments, **params)
    ["/training/green-dot/session/#{@art_slot.id}", *segments].join("/") +
      (params.any? ? "?#{params.to_query}" : "")
  end
end
