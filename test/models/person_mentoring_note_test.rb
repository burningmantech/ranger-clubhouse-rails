# frozen_string_literal: true

require "test_helper"

# General notes (ruled 2026-10-27): every year's, about the people asked for,
# newest first, each with its author.
class PersonMentoringNoteTest < ActiveSupport::TestCase
  test "a mentee's notes come newest first, with their authors, and nobody else's" do
    mentee = person(:alpha_ranger)
    older = PersonMentoringNote.create!(person: mentee, written_by: person(:active_ranger), notes: "First walk.",
                                        created_at: 2.years.ago)
    newer = PersonMentoringNote.create!(person: mentee, written_by: person(:echelon_ranger), notes: "Second walk.")
    PersonMentoringNote.create!(person: person(:active_ranger), written_by: mentee, notes: "Someone else.")

    notes = PersonMentoringNote.for_people([mentee.id]).to_a

    assert_equal [newer, older], notes
    assert notes.all? { |note| note.association(:written_by).loaded? }
  end
end
