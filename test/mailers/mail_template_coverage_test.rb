# frozen_string_literal: true

require "test_helper"

# Every message the Clubhouse can send needs wording in the database, or nothing
# goes out. This is what stops a new mailer shipping without it.
class MailTemplateCoverageTest < ActionMailer::TestCase
  setup do
    Rails.application.eager_load!
  end

  # Only what each mailer declares itself. Anything inherited is a helper for
  # building a message, not a message of its own.
  def actions
    ApplicationMailer.descendants.flat_map do |mailer|
      mailer.public_instance_methods(false).map { |action| "#{mailer.mailer_name}/#{action}" }
    end.sort
  end

  test "every message has wording" do
    assert_predicate actions, :any?, "no mailer actions were found to check"

    missing = actions.reject { |tag| MailTemplate.exists?(tag: tag) }

    assert_empty missing, "no wording loaded for: #{missing.join(", ")}"
  end

  test "every message has a subject" do
    without = actions.select { |tag| MailTemplate.find_by(tag: tag)&.subject.blank? }

    assert_empty without, "no subject for: #{without.join(", ")}"
  end

  test "no wording is left over from a message that no longer exists" do
    known = actions.to_set
    stray = MailTemplate.where.not(tag: known).reject(&:shared_piece?).map(&:tag)

    assert_empty stray, "wording with no message to send it: #{stray.join(", ")}"
  end
end
