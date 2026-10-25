# frozen_string_literal: true

require "test_helper"

class MailTemplateRendererTest < ActiveSupport::TestCase
  test "values are read by name whether the mailer used words or symbols" do
    assert_equal "Hi Hardly", MailTemplateRenderer.render("Hi {{ name }}", { name: "Hardly" })
    assert_equal "Hi Hardly", MailTemplateRenderer.render("Hi {{ name }}", { "name" => "Hardly" })
  end

  test "nested groups and lists are readable" do
    values = { person: { callsign: "Hardly" }, shifts: [{ title: "Dirt" }, { title: "Gate" }] }
    source = "{{ person.callsign }}: {% for shift in shifts %}{{ shift.title }} {% endfor %}"

    assert_equal "Hardly: Dirt Gate ", MailTemplateRenderer.render(source, values)
  end

  test "an HTML part escapes what a person typed" do
    rendered = MailTemplateRenderer.render("{{ message }}", { message: "<script>alert(1)</script>" })

    assert_equal "&lt;script&gt;alert(1)&lt;/script&gt;", rendered
  end

  test "an HTML part escapes a value nested inside a list" do
    source = "{% for row in rows %}{{ row.name }}{% endfor %}"
    rendered = MailTemplateRenderer.render(source, { rows: [{ name: "<b>x</b>" }] })

    assert_equal "&lt;b&gt;x&lt;/b&gt;", rendered
  end

  test "text already prepared as HTML is left alone" do
    prepared = ActionController::Base.helpers.simple_format("one\n\ntwo")
    rendered = MailTemplateRenderer.render("{{ message }}", { message: prepared })

    assert_equal "<p>one</p>\n\n<p>two</p>", rendered
  end

  test "a plain text part is never escaped" do
    rendered = MailTemplateRenderer.render("{{ note }}", { note: "Bring rope & water" },
                                          escape_html: false)

    assert_equal "Bring rope & water", rendered
  end

  test "a value the template does not know about renders as nothing" do
    assert_equal "Hi ", MailTemplateRenderer.render("Hi {{ noone }}", {})
  end
end
