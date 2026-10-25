# frozen_string_literal: true

require "test_helper"

class MailTemplateTest < ActiveSupport::TestCase
  def build(**overrides)
    MailTemplate.new({
      tag: "test_mailer/notify",
      description: "A message used by the tests",
      subject: "Hello {{ name }}",
      body: "<p>Hello {{ name }}</p>"
    }.merge(overrides))
  end

  test "a template whose parts all parse is valid" do
    assert_predicate build, :valid?
  end

  test "a body that does not parse is refused" do
    template = build(body: "{% if %}")

    assert_not_predicate template, :valid?
    assert_predicate template.errors[:body], :any?
  end

  test "a subject that does not parse is reported against the subject" do
    template = build(subject: "{{ name")

    assert_not_predicate template, :valid?
    assert_predicate template.errors[:subject], :any?
    assert_empty template.errors[:body]
  end

  test "a plain text part that does not parse is refused" do
    template = build(text_body: "{% for %}")

    assert_not_predicate template, :valid?
    assert_predicate template.errors[:text_body], :any?
  end

  test "a tag with spaces is refused" do
    assert_not_predicate build(tag: "test mailer/notify"), :valid?
  end

  test "source_for answers only the parts the message has" do
    template = build(text_body: nil)

    assert_equal "<p>Hello {{ name }}</p>", template.source_for(:html)
    assert_nil template.source_for(:text)
  end
end
