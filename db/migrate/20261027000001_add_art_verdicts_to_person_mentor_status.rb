# frozen_string_literal: true

# Two verdicts an ART walk may end with besides the four every walk has
# (ruled 2026-10-27): abstain, the mentor declined to give a verdict, and
# not-completed, the mentee did not complete the shift. Only an ART's roster
# offers them; the Alpha pages keep the four (PersonMentor::ALPHA_STATUSES).
#
# Appended to the end of the list, so every stored value keeps its index: an
# enum is stored, and sorted, by its index.
#
# down guards db:rollback only. An image rolled back past this change leaves
# the column wide, and its roster draws a walk holding either verdict with no
# matching Result option: the browser sends the select's first option instead,
# and a save of that shift rewrites the verdict. Change those walks before
# rolling the image back.
class AddArtVerdictsToPersonMentorStatus < ActiveRecord::Migration[8.1]
  STATUSES = %w[pass bonk self-bonk pending].freeze
  ART_VERDICTS = %w[abstain not-completed].freeze

  def up
    change_column :person_mentor, :status, enum_type(STATUSES + ART_VERDICTS)
  end

  # Refuses while a row holds either verdict, naming the cause rather than
  # failing on the first row the narrower list cannot hold.
  def down
    if select_value("SELECT 1 FROM person_mentor WHERE status IN ('abstain', 'not-completed') LIMIT 1")
      raise ActiveRecord::IrreversibleMigration,
            "person_mentor holds Abstained or Not completed verdicts; change them before narrowing the status list"
    end

    change_column :person_mentor, :status, enum_type(STATUSES)
  end

  private

  def enum_type(values) = "enum(#{values.map { |value| "'#{value}'" }.join(",")})"
end
