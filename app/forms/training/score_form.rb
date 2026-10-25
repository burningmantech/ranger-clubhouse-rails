# frozen_string_literal: true

# The score dialog's form: the trainee's status (pending, passed, no-show or
# not-passed), rank, a new note, and (In-Person only) whether feedback was
# delivered. Carries the upstream client-side rules
# server-side: a passing trainee who needs ranking must get a rank, and any
# rank other than Average needs a note unless a prior trainer note already
# justifies it.
class Training::ScoreForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :status, :string
  attribute :rank, :integer
  attribute :note, :string
  attribute :feedback_delivered, :boolean

  # The TrainingSession::Trainee being scored, for need_ranking and the
  # prior-notes check.
  attr_accessor :trainee

  validates :status, inclusion: { in: TraineeStatus::STATUSES, message: "Choose a training result." }
  validates :rank, inclusion: { in: TrainingSession::RANK_LABELS.keys }, allow_nil: true
  validate :rank_required_for_non_actives
  validate :note_required_for_non_average_ranks

  # A form pre-filled from the trainee's current score, for the edit dialog.
  # @param trainee [TrainingSession::Trainee]
  # @return [Training::ScoreForm]
  def self.for(trainee)
    new(status: trainee.training_status, rank: trainee.rank, feedback_delivered: trainee.feedback_delivered)
  end

  private

  def rank_required_for_non_actives
    return unless status == TraineeStatus::STATUS_PASSED && trainee&.need_ranking && rank.nil?

    errors.add(:rank, "A rank is required: #{trainee.person.callsign} must be ranked before passing.")
  end

  def note_required_for_non_average_ranks
    return unless TrainingSession::NOTE_REQUIRED_RANKS.include?(rank)
    return if note.present? || trainee&.trainer_notes&.any?

    errors.add(:note, "A training note is required when giving a rank other than 2 — Average.")
  end
end
