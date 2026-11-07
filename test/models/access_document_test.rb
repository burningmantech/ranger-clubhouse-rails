# frozen_string_literal: true

require "test_helper"

class AccessDocumentTest < ActiveSupport::TestCase
  # The note is prepended to the comments in before_save, after the column
  # check has run, so the model measures the room it will take beforehand.
  test "a comment the comments column cannot hold is refused before saving" do
    document = access_document(:ar_staff_credential)
    document.additional_comments = "x" * 66_000

    assert_not document.save
    assert_equal ["The comment is too long to save with the comments already on this document. Shorten it and try again."],
                 document.errors[:additional_comments]

    document.additional_comments = "Handed over at the gate."
    assert document.save, document.errors.full_messages.join(" ")
    assert_includes document.reload.comments, "Handed over at the gate."
  end
end
