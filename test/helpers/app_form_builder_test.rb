# frozen_string_literal: true

require "test_helper"

class AppFormBuilderTest < ActionView::TestCase
  include FormHelper

  class MockPerson
    include ActiveModel::Model
    attr_accessor :name, :email, :age, :bio, :terms, :status, :country

    validates :name, presence: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  end

  setup do
    @person = MockPerson.new(name: "John Doe", email: "john@example.com")
  end

  test "text_field generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Full Name" %>
      <% end %>
    ERB

    assert_select "label.block.mb-1.font-medium.text-heading", text: "Full Name"
    assert_select "input[type=text].input"
  end

  test "text_field with required option shows indicator" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Full Name", required: true %>
      <% end %>
    ERB

    # The indicator has to live inside the <label> so it is announced as part of
    # the field name. What markup carries it is styling, and is not pinned.
    assert_select "label", text: /Full Name.*required/i
    assert_select "input[required]"
  end

  test "email_field generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.email_field :email, label: "Email Address" %>
      <% end %>
    ERB

    assert_select "label", text: "Email Address"
    assert_select "input[type=email]"
  end

  test "text_area generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_area :bio, label: "Biography" %>
      <% end %>
    ERB

    assert_select "label", text: "Biography"
    assert_select "textarea.textarea"
  end

  # ------------------------------------------------------------ rich_text_area

  test "rich_text_area renders the editor as the field itself, holding what was saved" do
    @person.bio = "<p>Written <strong>earlier</strong></p>"

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography", required: true, help_text: "Say a little." %>
      <% end %>
    ERB

    editor = css_select("lexxy-editor").first
    assert editor, "no <lexxy-editor> was rendered"

    # It submits under its own name: nothing else carries the value.
    assert_match(/\[bio\]\z/, editor["name"])
    assert_equal "<p>Written <strong>earlier</strong></p>", editor["value"]
    assert_select "input[type=hidden][name$='[bio]']", count: 0

    # One id serves the label, and the help text is what describes it.
    assert_select "label[for=?]", editor["id"], text: /Biography/
    assert_equal "#{editor["id"]}_hint", editor["aria-describedby"]
    assert_select "##{editor["id"]}_hint", text: "Say a little."

    # Lexxy sets aria-required from `required` itself, so only the attribute is written.
    assert editor.key?("required")
    assert_nil editor["aria-required"]

    # No uploads, the lazy loader, a page update that leaves the editor alone,
    # and the rules that style what is being typed.
    assert_equal "false", editor["attachments"]
    assert_includes editor["data-controller"].split, "lexxy"
    assert editor.key?("data-morph-skip")
    assert_includes editor["class"].split, "lexxy-content"
  end

  # The tag helper escapes only the quotes of a SafeBuffer. Text that was saved
  # as &lt;b&gt; and then marked safe would reach the editor as a real <b> tag,
  # so the value goes in as a plain String, whatever it was marked as.
  test "rich_text_area hands the editor text as text, whatever it was marked as" do
    @person.bio = ActiveSupport::SafeBuffer.new("&lt;b&gt; is how bold is written")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography" %>
      <% end %>
    ERB

    assert_equal "&lt;b&gt; is how bold is written", css_select("lexxy-editor").first["value"]
  end

  # The editor keeps no image, so saving text that has one removes it. The form
  # says so before the save. The image is also taken out of what the editor is
  # handed: left in, it is dropped there with the spaces on either side of it.
  test "rich_text_area warns that images will be removed, and keeps the words around one apart" do
    @person.bio = %(<p>Press <img src="/icon.png"> to continue.</p><p><a href="https://example.com"><img src="/a.png"></a></p>)

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography" %>
      <% end %>
    ERB

    assert_select "[role=alert]", text: /This text has 2 images, which the editor cannot keep\. Saving removes them\./
    value = Nokogiri::HTML5.fragment(css_select("lexxy-editor").first["value"])
    assert_equal "Press to continue.", value.at_css("p").text.squish
    assert_empty value.css("img, a"), "the image, and the link that held nothing else, are both gone"
  end

  test "rich_text_area says nothing about images when the text has none, and one image reads as one" do
    @person.bio = "<p>Words only</p>"
    @person.status = %(<p><img src="/a.png"> One</p>)

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography" %>
        <%= f.rich_text_area :status, label: "Status" %>
      <% end %>
    ERB

    assert_select "[role=alert]", count: 1, text: /This text has an image, which the editor cannot keep\. Saving removes it\./
  end

  # A form that comes back from a rejected save holds what the editor sent, which
  # has no image left in it. The saved text still has every one, and the saved
  # text is what the warning is about.
  test "rich_text_area still warns about an image on file when the form comes back from a rejected save" do
    announcement = motd(:ranger_announcement)
    announcement.update_column(:message, %(<p>Gate map <img src="/map.png"></p>))
    announcement.message = "<p>Gate map</p>"

    render inline: <<~ERB, locals: { announcement: }
      <%= ui_form(announcement, "/announcements") do |f| %>
        <%= f.rich_text_area :message, label: "Message" %>
      <% end %>
    ERB

    assert_select "[role=alert]", text: /This text has an image, which the editor cannot keep\./
    assert_equal "<p>Gate map</p>", css_select("lexxy-editor").first["value"]
  end

  # The editor puts "https://" in front of a link it takes for a bare host name,
  # which is wrong for a link written relative to a folder. "./" says the same
  # thing in a form the editor leaves alone. Everything else is its business.
  test "rich_text_area keeps a link that is relative to a folder pointing where it did" do
    hrefs = %w[docs/map.pdf me/schedule /me/x ../up www.example.org/page map.pdf mailto:a@b.c https://x.y/z #top ?year=2024]
    @person.bio = safe_join(hrefs.map { |href| tag.a("link", href:) })

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography" %>
      <% end %>
    ERB

    handed = Nokogiri::HTML5.fragment(css_select("lexxy-editor").first["value"]).css("a").map { |link| link["href"] }
    assert_equal %w[./docs/map.pdf ./me/schedule] + hrefs.drop(2), handed
  end

  test "rich_text_area marks a field with errors by its border, and keeps any controller already set" do
    @person.valid?
    @person.errors.add(:bio, "can't be blank")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.rich_text_area :bio, label: "Biography", width: "w-full", data: { controller: "autosave" } %>
      <% end %>
    ERB

    editor = css_select("lexxy-editor").first
    assert_equal %w[autosave lexxy], editor["data-controller"].split
    # A plain utility, which beats the vendored chrome because that sits in a layer.
    assert_equal %w[lexxy-content w-full border-error border-2], editor["class"].split
    assert_select "div[role=alert]", text: /can't be blank/
    assert_select "label.text-error"
  end

  test "select generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.select :country, [["USA", "us"], ["Canada", "ca"]], { label: "Country" } %>
      <% end %>
    ERB

    assert_select "label", text: "Country"
    assert_select "select.select"
  end

  test "collection_select supports builder options in html_options slot" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_select :country,
            [["USA", "us"], ["Canada", "ca"]],
            :last, :first,
            { include_blank: "Select a country" },
            { label: "Country", required: true, help_text: "Pick one", class: "font-mono" } %>
      <% end %>
    ERB

    assert_select "label", text: /Country.*required/i
    assert_select "select.select.font-mono[required][aria-describedby]"
    assert_select "div.mt-1.text-sm.text-body", text: "Pick one"
  end

  test "check_box generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.check_box :terms, label: "I agree" %>
      <% end %>
    ERB

    assert_select "input[type=checkbox].checkbox"
    assert_select "label span", text: "I agree"
  end

  test "radio_button generates proper markup" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.radio_button :status, "active", label: "Active" %>
      <% end %>
    ERB

    assert_select "input[type=radio].radio"
    assert_select "label", text: "Active"
  end

  test "field with help_text shows help text" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Name", help_text: "Enter your full name" %>
      <% end %>
    ERB

    assert_select "div.mt-1.text-sm.text-body", text: "Enter your full name"
    assert_select "input[aria-describedby]"
  end

  test "field with errors shows error message" do
    @person.valid?
    @person.errors.add(:name, "can't be blank")

    @person.errors.add(:terms, "must be accepted")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Name" %>
        <%= f.check_box :terms, label: "I agree" %>
        <%= f.text_field :email, label: "Email" %>
      <% end %>
    ERB

    assert_select "input.input-error[aria-invalid=true]"
    assert_select "input[type=checkbox].checkbox-error[aria-invalid=true]"
    assert_select "input[aria-invalid]", count: 2, message: "a field with no error is not marked invalid"
    assert_select "div[role=alert]", text: /can't be blank/
    assert_select "label.text-error"
  end

  # A fieldset has no field of its own to hang these on, so a view draws them
  # through the builder rather than copying their markup.
  test "a view can draw a group's own help and error lines through the builder" do
    @person.errors.add(:country, "Choose a country.")
    @person.errors.add(:country, "That country is not offered.")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people", no_error_summary: true) do |f| %>
        <%= f.help_text_tag("Pick one.", "country-help") %>
        <%= f.error_message(:country, "country-error") %>
        <%= f.error_message(:name, "name-error") %>
      <% end %>
    ERB

    assert_select "div#country-help.text-sm", text: "Pick one."
    assert_select "div#country-error[role=alert] span", text: "Choose a country. That country is not offered."
    assert_select "#name-error", count: 0, message: "a field with no error draws nothing"
  end

  # A comma between two sentences reads "Choose a country., That country...".
  test "a field's error line joins whole sentences with a space and fragments with a comma" do
    @person.errors.add(:country, "Choose a country.")
    @person.errors.add(:country, "That country is not offered.")
    @person.errors.add(:name, "is too short")
    @person.errors.add(:name, "is invalid")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people", no_error_summary: true) do |f| %>
        <%= f.text_field :country, label: "Country" %>
        <%= f.text_field :name, label: "Name" %>
      <% end %>
    ERB

    assert_select "div[role=alert] span", text: "Choose a country. That country is not offered."
    assert_select "div[role=alert] span", text: "is too short, is invalid"
  end

  test "form displays error summary when model has errors" do
    @person.name = ""
    @person.email = "invalid"
    @person.valid?

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name %>
      <% end %>
    ERB

    assert_select "div.box.box-error", count: 1
    assert_select "div.font-semibold", text: /Please fix the following/
  end

  test "form without error summary skips error display" do
    @person.name = ""
    @person.valid?

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people", no_error_summary: true) do |f| %>
        <%= f.text_field :name %>
      <% end %>
    ERB

    assert_select "div.box.box-error", count: 0
  end

  test "submit button has proper styling" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.submit "Save" %>
      <% end %>
    ERB

    assert_select "input[type=submit].btn"
    assert_select "input[type=submit].btn-primary"
  end

  test "field without wrapper skips wrapper div" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, wrapper: false %>
      <% end %>
    ERB

    assert_select "div.mb-3 > input[type=text]", count: 0
    assert_select "input[type=text]", count: 1
  end

  test "custom wrapper class is applied" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, wrapper_class: "mb-10 custom-class" %>
      <% end %>
    ERB

    assert_select "div.mb-10.custom-class"
  end

  test "custom field class is merged with default classes" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, class: "font-mono" %>
      <% end %>
    ERB

    assert_select "input.input.font-mono"
  end

  test "fieldset groups fields with legend" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.fieldset "Personal Info" do %>
          <%= f.text_field :name, label: "Name" %>
        <% end %>
      <% end %>
    ERB

    assert_select "fieldset"
    assert_select "legend", text: "Personal Info"
    assert_select "fieldset div.space-y-3"
  end

  test "horizontal layout renders with responsive classes" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people", layout: :horizontal) do |f| %>
        <%= f.text_field :name, label: "Name" %>
      <% end %>
    ERB

    assert_select "div.flex.flex-col.lg\\:flex-row"
    # Horizontal means the label sits beside the input instead of stacked above
    # it (the vertical default is "block mb-1"). Alignment inside that column is
    # styling, not behaviour, so it is not asserted.
    assert_select "label", text: "Name"
    assert_select "label.block.mb-1", count: 0
  end

  test "form_row creates responsive row" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= form_row do %>
          <%= f.text_field :name, label: "Name" %>
          <%= f.email_field :email, label: "Email" %>
        <% end %>
      <% end %>
    ERB

    assert_select "div.flex.flex-col.lg\\:flex-row.gap-3"
  end

  test "DaisyUI input class is applied" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Name" %>
      <% end %>
    ERB

    assert_select "input.input"
  end

  test "compact wrapper spacing is applied" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.text_field :name, label: "Name" %>
      <% end %>
    ERB

    assert_select "div.mb-3"
  end

  test "uses tag builder for fieldset" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.fieldset "Contact" do %>
          <%= f.email_field :email, label: "Email" %>
        <% end %>
      <% end %>
    ERB

    assert_select "fieldset.form-fieldset"
    assert_select "fieldset > legend"
    assert_select "fieldset > div.space-y-3"
  end

  test "collection_radio_buttons default behavior is inline" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", layout: :horizontal } %>
      <% end %>
    ERB

    # Label should be a span (inline beside radios)
    assert_select "span.font-medium.text-heading", text: "Status"
    # Wrapper should use horizontal layout with lg:flex-row
    assert_select "div.lg\\:flex-row"
  end

  test "collection_radio_buttons with label_position stacked on horizontal layout" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", layout: :horizontal, label_position: :stacked } %>
      <% end %>
    ERB

    # Label should be a legend inside a radiogroup fieldset (accessible group name)
    assert_select "fieldset[role=radiogroup] legend.block.mb-1.font-medium.text-heading", text: "Status"
    # Wrapper should NOT use lg:flex-row (would force side-by-side)
    assert_select "div.lg\\:flex-row", count: 0
    # Wrapper should be the vertical fieldset wrapper
    assert_select "fieldset.mb-3"
    # Radio buttons should still use horizontal multi-column orientation classes
    assert_select "div.columns-1.sm\\:columns-2"
  end

  test "collection_radio_buttons with label_position stacked on auto layout" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", layout: :auto, label_position: :stacked } %>
      <% end %>
    ERB

    # Label should be a legend inside a radiogroup fieldset (accessible group name)
    assert_select "fieldset[role=radiogroup] legend.block.mb-1.font-medium", text: "Status"
    # Wrapper should NOT use lg:flex-row (would force side-by-side)
    assert_select "div.lg\\:flex-row", count: 0
    # Wrapper should be the vertical fieldset wrapper
    assert_select "fieldset.mb-3"
    # Radio buttons should still use auto multi-column orientation classes
    assert_select "div.space-y-1.lg\\:columns-2"
  end

  test "collection_radio_buttons with invalid label_position falls back to inline" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", layout: :horizontal, label_position: :invalid } %>
      <% end %>
    ERB

    # Should fall back to inline (span with horizontal label classes)
    assert_select "span.font-medium.text-heading", text: "Status"
    # Wrapper should use horizontal layout with lg:flex-row
    assert_select "div.lg\\:flex-row"
  end

  test "collection_radio_buttons stacked preserves radio orientation classes" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"], ["Pending", "pending"]],
            :last, :first,
            { label: "Status", layout: :horizontal, label_position: :stacked } %>
      <% end %>
    ERB

    # Verify horizontal orientation is preserved inside stacked fieldset wrapper
    assert_select "div.columns-1.sm\\:columns-2" do
      assert_select "input[type=radio]", count: 3
    end
  end

  test "collection_radio_buttons stacked displays field suffix correctly" do
    @person.valid?
    @person.errors.add(:status, "must be selected")

    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", layout: :horizontal, label_position: :stacked } %>
      <% end %>
    ERB

    # Error message should still appear
    assert_select "div[role=alert]", text: /must be selected/
  end

  test "collection_radio_buttons vertical layout ignores label_position" do
    render inline: <<~ERB, locals: { person: @person }
      <%= ui_form(person, "/people") do |f| %>
        <%= f.collection_radio_buttons :status,
            [["Active", "active"], ["Inactive", "inactive"]],
            :last, :first,
            { label: "Status", label_position: :stacked } %>
      <% end %>
    ERB

    # Vertical layout uses fieldset/legend, so label_position doesn't apply
    assert_select "fieldset"
    assert_select "legend", text: "Status"
  end
end
