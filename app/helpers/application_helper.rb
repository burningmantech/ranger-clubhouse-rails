module ApplicationHelper
  include BasicCacheHelper
  include ButtonHelper
  include CreditHelper
  include FormHelper
  include GenderHelper
  include IconHelper
  include LinkHelper
  include PageLayoutHelper
  include PronounsHelper
  include SidebarHelper
  include ShirtHelper
  include CountryStateHelper
  include TurboHelper
  include UiComponentsHelper
  include UiComponents::UiHeroPanelHelper
  include YearHelper
  include ModalHelper

  include ActionView::Helpers::TextHelper

  TELEPHONE_REGEXP = /(\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}/

  # One name per qualification item, shared by its row and the Next Step sentence.
  QUALIFICATION_NAMES = {
    spt: "Special Price Ticket",
    staff_credential: "Staff Credential",
    event_week_eats: "Event Week Eat Pass",
    all_eats: "All Eat Meal Pass",
    t_shirt: "Ranger T-Shirt",
    long_sleeve_shirt: "Ranger Long Sleeve Shirt",
    shower_pog: "Wet Spot Pog for THIS event",
    shower_access_event_week: "Wet Spot Access for NEXT event (Event Week hours)",
    shower_access_entire_event: "Wet Spot Access for NEXT event (Combined hours)"
  }.freeze

  # When a counter's hours have to fall. Credits and all counted hours can fall any time.
  QUALIFICATION_PERIODS = {
    event_week: "during Event Week",
    pre_event_and_event_week: "during Pre-Event or Event Week"
  }.freeze

  # A section's badge label and ui_badge variant, by QualificationsPresenter state.
  QUALIFICATION_VERDICTS = {
    earned: ["Earned", :success],
    on_track: ["On Track", :primary],
    needs_sign_ups: ["Needs Sign-Ups", :secondary],
    closed: ["Not This Year", :secondary]
  }.freeze

  def setting(name)
    Setting.get_value(name)
  end

  def phone_format(number)
    PhoneFormatter.format(number)
  end

  def dropdown_scroll_list(items)
    letters = {}
    items.each do |item|
      char = item.title[0].upcase
      (letters[char] ||= []) << item
    end

    list = letters.map do |letter, links|
      [letter, links]
    end
    list.sort_by! { |letter| letter[0] }

    render partial: "common/dropdown_scroll_list", locals: { letters: list }
  end

  def none_stated
    content_tag(:i, "None stated", class: "text-stone-muted")
  end

  def value_or_dash(value)
    value.presence || "—"
  end

  # A team's or position's title, with "(inactive)" appended when it is not
  # active. Records must respond to #active? and #title.
  def title_marking_inactive(record)
    record.active? ? record.title : "#{record.title} (inactive)"
  end

  # Positions as grouped select choices, [team title, [[label, id], ...]], with
  # inactive ones marked. A page that draws several selects from one list builds
  # this once and hands it to grouped_options_for_select for each.
  def position_choices_by_team(positions)
    PositionGroups.by_team(positions)
                  .map { |title, list| [title, list.map { |position| [title_marking_inactive(position), position.id] }] }
  end

  # A table cell holding several values: one per line, or a dash when there are
  # none. Used where a row carries a short list -- role grants, attribute
  # labels -- that a run-on sentence would make unscannable.
  def value_list(items)
    return value_or_dash(nil) if items.blank?

    tag.div(class: "flex flex-col gap-1") do
      safe_join(items.map { |item| tag.div(item) })
    end
  end

  # Table cell for an expiring date: ISO date plus an "Expired" badge once
  # past, or the fallback when no expiry is set. Records must respond to
  # #expires_on and #has_expired?.
  def expires_on_cell(record, fallback: "—")
    return fallback if record.expires_on.blank?

    tag.div(class: "flex flex-wrap items-center gap-2") do
      parts = [tag.span(record.expires_on.iso8601)]
      parts << ui_badge("Expired", :warning, icon: "triangle-exclamation", icon_type: :solid) if record.has_expired?
      safe_join(parts)
    end
  end

  def photo_tag(photo, options = {})
    if photo.attached?
      options[:loading] = "lazy"
      # Never leave an <img> unlabelled: with no alt a screen reader reads the
      # URL aloud. Decorative by default, so a caller that has a name passes one.
      options[:alt] ||= ""
      options[:style] = "width: #{options.delete(:width)}px;#{options[:style]} " if options[:width]
      options[:style] = "height: #{options.delete(:height)}px;#{options[:style]} " if options[:height]
      # Paths: a live list row is rendered outside any request, where a URL's
      # host is the renderer's example.org.
      url = Rails.env.development? ? rails_storage_proxy_path(photo) : url_for(photo)
      image_tag url, options
    else
      fa_icon "user"
    end
  end

  # What a plain text field's own markup may carry: Rails' default allow-list
  # less class. Nothing typed needs one, and the app's own utilities would let
  # a message cover the reader's screen (review finding 8).
  PLAIN_TEXT_ATTRIBUTES = (Rails::HTML5::SafeListSanitizer.allowed_attributes - %w[class]).freeze

  # A plain text field ready to render: its own markup sanitized, and its web
  # and email addresses, phone numbers and line breaks made into links and
  # <br>s -- found in its text alone, one text node at a time. Matched in the
  # sanitized HTML instead, a link landed inside an attribute's quotes and
  # turned the rest of the value into live markup: a title holding a phone
  # number, or a URL after a ">", let any member's message run script in its
  # reader's page. Markup nested deeper than the HTML5 parser goes (400
  # levels), which no editor writes, is shown as typed, escaped.
  def hyperlink_text(text)
    fragment = begin
      Nokogiri::HTML5.fragment(sanitize(text.to_s, attributes: PLAIN_TEXT_ATTRIBUTES))
    rescue ArgumentError # "Document tree depth limit exceeded"
      return safe_join(text.to_s.split("\n", -1), tag.br)
    end
    # descendant-or-self: on a fragment, ".//text()[...]" skips the text at its top level.
    fragment.xpath("descendant-or-self::text()[not(ancestor::a)]").each { |node| node.replace(hyperlinked_text(node.content)) }
    fragment.to_html(preserve_newline: true).html_safe
  end

  def nl2br(text)
    return "" if text.blank?
    h(text).gsub(/\n/, "<br>").html_safe
  end

  # What a saved rich text field may carry beyond Rails' default safelist: tables
  # (documents from the old editor have them, and Lexxy wraps the ones it writes
  # in a <figure>), Lexxy's strikethrough and underline -- the default list has
  # neither <s> nor <u>, so both would render as plain text -- the two attributes
  # that keep a numbered list's numbering, and the two that keep a merged table
  # cell merged: without them a cell's neighbours slide into the wrong columns.
  RICH_TEXT_TAGS = (Rails::HTML5::SafeListSanitizer.allowed_tags + %w[table thead tbody tfoot tr td th figure s u]).freeze
  RICH_TEXT_ATTRIBUTES = (Rails::HTML5::SafeListSanitizer.allowed_attributes + %w[start value colspan rowspan]).freeze

  # The classes Lexxy writes into what it saves, which lexxy-content.css styles:
  # a table's wrapper (it scrolls a wide table), a header cell, a divider, the
  # text formats. No other class is kept. With the app's own utilities a message
  # covered the reader's screen with a page of its own (review finding 8,
  # class="fixed inset-0 z-50 bg-base-100").
  RICH_TEXT_CLASS = /\A(?:lexxy-content__[a-z_-]+|horizontal-divider)\z/

  # RICH_TEXT_TAGS and RICH_TEXT_ATTRIBUTES, with each class cut to the
  # RICH_TEXT_CLASS ones.
  class RichTextScrubber < Rails::HTML::PermitScrubber
    def initialize
      super
      self.tags = RICH_TEXT_TAGS
      self.attributes = RICH_TEXT_ATTRIBUTES
    end

    protected

    def scrub_attribute(node, attr_node)
      return super unless attr_node.name == "class"

      classes = attr_node.value.split.grep(RICH_TEXT_CLASS)
      classes.empty? ? attr_node.remove : attr_node.value = classes.join(" ")
    end
  end
  RICH_TEXT_SCRUBBER = RichTextScrubber.new

  # A saved rich text field, ready to render. Sanitized rather than trusted: the
  # column holds whatever was posted, and the editor is only a client-side
  # convenience.
  def rich_text(html)
    sanitize html, scrubber: RICH_TEXT_SCRUBBER
  end

  def hour_not_counted_disclaimer(is_training = false)
    content_tag :div, class: "my-2 text-sm" do
      "Note: The #{is_training ? "time spent in this training does" : "on duty hours volunteered in this position do"} not qualify for provisions (meals, showers, clothing, or an event radio).
        This applies to provisions only and does not affect any credit earnings or ticket eligibility."
    end
  end

  def back_to(label, url, options = {})
    options = options.dup
    icon = options.delete(:icon) || "arrow-left"
    icon_type = options.delete(:icon_type) || :solid
    aria_label = options.delete(:aria_label) || "Back to #{label}"

    # Subtle text link style (breadcrumb pattern)
    link_class = "inline-flex-center-gap-2 min-h-9 text-body no-decoration " \
      "hover:text-stone-emphasis transition-colors"

    link_to url, class: link_class, aria: { label: aria_label } do
      safe_join([
                  fa_icon(icon, icon_type),
                  content_tag(:span, label)
                ])
    end
  end

  def back_to_dashboard
    back_to "Clubhouse Dashboard", me_root_path
  end

  # One yes/no answer in a report table. Icon as well as colour: the answer has
  # to survive a greyscale screen and a colour-blind reader. Lived in
  # Ticketing::AccessDocumentsHelper until a fourth namespace wanted it.
  def yes_no_badge(answer)
    if answer
      ui_badge("Yes", :success, icon: "circle-check", icon_type: :solid)
    else
      ui_badge("No", :secondary, icon: "circle-minus", icon_type: :solid)
    end
  end

  # Icon as well as colour: the state has to survive a greyscale screen or a
  # sunlit phone. The row puts the words beside it. Not yet is neutral: an unmet
  # goal is not a warning, and most Rangers never aim at every one; a closed one
  # is a minus in the same grey (solid: the free regular weight has no circle-minus,
  # and a name the font lacks renders as a box).
  def qualification_icon(item)
    if item.has_earned
      fa_icon "circle-check", :solid, class: "icon-success"
    elsif item.expected_to_earn
      fa_icon "hourglass-half", :solid, class: "text-primary"
    elsif item.closed
      fa_icon "circle-minus", :solid, class: "text-stone-icon"
    else
      fa_icon "circle", :regular, class: "text-stone-icon"
    end
  end

  def qualification_name(item) = QUALIFICATION_NAMES.fetch(item.name)

  # "Sign up for 18 hr more during Event Week to earn the Event Week Eat Pass and 1 more."
  # step is a QualificationsPresenter::NextStep.
  def qualification_next_step(step)
    period = QUALIFICATION_PERIODS[step.item.counter]
    safe_join([
      "Sign up for ", tag.strong(qualification_amount(step.item.needs_to_schedule), class: "tabular-nums"), " more",
      (" #{period}" if period),
      " to earn the ", tag.strong(qualification_name(step.item)),
      (" and #{step.others} more" if step.others.positive?), "."
    ].compact)
  end

  # "5 of 6 earned, 1 needs more sign-ups", from QualificationsPresenter#goal_counts.
  # A tally holds no zeros, so a missing state is simply left out.
  def qualification_goal_counts(counts)
    needs = counts[:needs_sign_ups]
    [
      "#{counts.fetch(:earned, 0)} of #{counts.values.sum} earned",
      ("#{counts[:on_track]} on track" if counts[:on_track]),
      ("#{needs} #{needs == 1 ? "needs" : "need"} more sign-ups" if needs),
      ("#{counts[:closed]} not this year" if counts[:closed])
    ].compact.join(", ")
  end

  # A qualifications page section with its verdict badge; no badge when the section
  # holds no goals.
  def qualification_section(title, state, &)
    label, color = QUALIFICATION_VERDICTS[state]
    ui_section(title, badge: label, badge_color: color, html: { aria: { label: "#{title} Qualification" } }, &)
  end

  # The progress lib hands amounts over as words ("117 hours and 42 minutes"; the
  # HQ page prints them as they are). Two items share a line here, and the long
  # form wraps the next step under the name: "117 hr 42 min", and no zero half.
  def qualification_amount(words)
    words.to_s.delete_suffix(" and 0 minutes").sub(" and ", " ").gsub(/hours?/, "hr").gsub(/minutes?/, "min")
  end

  # The unit printed after a threshold, matching qualification_amount.
  def qualification_unit(item)
    item.measure == TicketsAndProvisionsProgress::MEASURE_HOURS ? "hr" : item.measure.to_s
  end

  private

  # One text node of a plain text field, as markup: its web and email
  # addresses linked (auto_link), then, in the text between those links, its
  # phone numbers and line breaks. It starts from the text escaped, so the only
  # tags in what auto_link hands back are the links it made.
  def hyperlinked_text(content)
    linked = auto_link(ERB::Util.html_escape(content).to_str, sanitize: false)
    linked.split(%r{(<a\b[^>]*>.*?</a>)}m).each_with_index.map do |part, index|
      next part if index.odd?

      part.gsub(TELEPHONE_REGEXP) { |number| link_to(number, "tel:#{number.gsub(/\D/, "")}") }.gsub("\n", "<br>")
    end.join
  end

  # "15.30 of 19.0 credits", "0 of 60 hr": the threshold printed beside it
  # already names the unit, so the amount done says it only when the two differ.
  def qualification_done(item)
    done = qualification_amount(item.value)
    return "0" if ["0 min", "zero credits"].include?(done)

    done.delete_suffix(" #{qualification_unit(item)}").delete_suffix(" credit")
  end
end
