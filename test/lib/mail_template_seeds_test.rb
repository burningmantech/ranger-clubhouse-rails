# frozen_string_literal: true

require "test_helper"

class MailTemplateSeedsTest < ActiveSupport::TestCase
  test "every template the Clubhouse ships is loaded and would be accepted" do
    assert_predicate MailTemplateSeeds.files, :any?, "no templates found to load"

    MailTemplateSeeds.files.each do |path|
      tag = MailTemplateSeeds.tag_for(path)
      template = MailTemplate.find_by(tag: tag)

      assert_not_nil template, "#{tag} was not loaded"
      assert_predicate template, :valid?, "#{tag}: #{template.errors.full_messages.join(", ")}"
    end
  end

  test "loading again changes nothing" do
    results = MailTemplateSeeds.load!

    assert_empty results[:created]
    assert_empty results[:updated]
    assert_empty results[:edited]
    assert_predicate results[:unchanged], :any?
  end

  test "a template edited in the Clubhouse is left alone and reported" do
    template = MailTemplate.find_by(tag: "password_reset_mailer/notify")
    template.update_columns(body: "<p>edited by hand</p>", updated_at: Time.current)

    results = MailTemplateSeeds.load!

    assert_includes results[:edited], template.tag
    assert_empty results[:updated]
    assert_equal "<p>edited by hand</p>", template.reload.body
  end

  test "a template the loader put there is brought up to date" do
    template = MailTemplate.find_by(tag: "password_reset_mailer/notify")
    values = MailTemplateSeeds.values_for(
      MailTemplateSeeds.files.find { |path| MailTemplateSeeds.tag_for(path) == template.tag }
    )

    # Stand where an older release would have left it: the wording it shipped
    # with, and a fingerprint saying that wording is untouched.
    template.update_columns(
      body: "<p>what an older release shipped</p>",
      seeded_digest: MailTemplateSeeds.digest_for(values.merge("body" => "<p>what an older release shipped</p>")),
      updated_at: Time.current
    )

    results = MailTemplateSeeds.load!

    assert_includes results[:updated], template.tag
    assert_equal values["body"], template.reload.body
  end

  test "a template made by hand is never overwritten" do
    MailTemplate.insert_all!(
      [{ tag: "test_mailer/handmade", description: "Made in the Clubhouse",
         body: "<p>mine</p>", created_at: Time.current, updated_at: Time.current }]
    )

    assert MailTemplateSeeds.edited?(MailTemplate.find_by(tag: "test_mailer/handmade")),
           "a template with no loaded fingerprint must be treated as edited"
  end

  # A link to Clubhouse 2's host, in capitals or not, sends the reader to
  # Clubhouse 2. A template names this Clubhouse as {{ clubhouse_url }}, or a
  # page by a value its mailer builds from a route.
  test "no template links to Clubhouse 2's host" do
    texts = MailTemplateSeeds.files.to_h { |path| [MailTemplateSeeds.tag_for(path), File.read(path)] }

    # The more-handles email's HandleAdvice link waits on #25, which decides
    # where it points. Only that one link, in that file, is let through, and once
    # #25 changes the line this fails until #25 removes the allowance too.
    handle_advice = "https://ranger-clubhouse.burningman.org/HandleAdvice"
    allowed = %(<a href="#{handle_advice}">#{handle_advice}</a>)
    more_handles = "prospective_application/more_handles_mailer/notify"
    assert_includes texts[more_handles], allowed, "#25 changed the link: remove its allowance here"
    texts[more_handles] = texts[more_handles].sub(allowed, "")

    assert_empty texts.select { |_tag, text| text.downcase.include?("ranger-clubhouse.burningman.org") }.keys,
                 "these templates write Clubhouse 2's host: link with {{ clubhouse_url }} or a route the mailer builds"
  end
end
