# frozen_string_literal: true

# A problem someone reported from the Bug Report link in the account menu, with
# enough about where they were and what they were using for the Tech Team to
# go and look.
class BugReport < ApplicationRecord
  self.table_name = "bug_report"

  DESCRIPTION_LIMIT = 5_000

  # The width of the url and user_agent columns.
  STRING_LIMIT = 255

  # How many reports the log page shows. The log is emptied rather than paged.
  LIST_LIMIT = 200

  belongs_to :person

  # The database refuses a value longer than its column outright, and that
  # would lose the report over a header the person never sees.
  normalizes :url, :user_agent, with: ->(value) { value.first(STRING_LIMIT) }

  # Whole sentences: the app prints a validation message as written, without
  # putting the field's name in front of it.
  validates :description,
            presence: { message: "Please describe what went wrong." },
            length: { maximum: DESCRIPTION_LIMIT,
                      message: "The report must be #{DESCRIPTION_LIMIT.to_fs(:delimited)} characters or fewer." }

  # What the log page shows: the newest reports, each with who filed it.
  scope :for_log, -> { order(id: :desc).includes(:person).limit(LIST_LIMIT) }

  # Delete every report and record who did it.
  #
  # @param actor [Person] who asked for the log to be emptied
  # @return [Integer] number of reports deleted
  def self.purge!(actor)
    # The wipe and the record of it stand or fall together -- a purge with no
    # audit line leaves no trace that it happened.
    transaction do
      count = delete_all
      ActionLog.record(actor, "bug-report-purge", "Deleted all bug reports", { count: count })
      count
    end
  end
end
