# frozen_string_literal: true

require "test_helper"

# The form objects defined a `submit` method that was invoked nowhere (every caller uses
# `.valid?`/`.invalid?`). It was deleted; this guards against it creeping back, and confirms
# the validation invariant each form actually carries still works.
class DeadSubmitRemovedTest < ActiveSupport::TestCase
  FORMS = [
    MessageForm, FindRecipientForm, MessageReplyForm, PasswordResetForm,
    LoginForm, SettingsSearchForm, PasswordUpdateForm, PasswordForm
  ].freeze

  test "no form object defines the removed #submit" do
    FORMS.each do |form|
      assert_not form.new.respond_to?(:submit), "#{form} should no longer define #submit"
    end
  end

  test "forms still enforce their validations" do
    assert_not LoginForm.new(email: "", password: "").valid?
    assert LoginForm.new(email: "ranger@example.com", password: "secret123").valid?

    assert_not FindRecipientForm.new(query: "x").valid?
    assert FindRecipientForm.new(query: "hardy").valid?
  end
end
