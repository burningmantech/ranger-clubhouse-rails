# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "year_range with empty array returns none text" do
    result = year_range([])
    assert_match(/none/, result)
  end

  test "year_range with nil returns none text" do
    result = year_range(nil)
    assert_match(/none/, result)
  end

  test "year_range with single year returns that year" do
    result = year_range([2023])
    assert_equal "2023", result
  end

  test "year_range with two consecutive years returns range" do
    result = year_range([2022, 2023])
    assert_equal "2022 - 2023", result
  end

  test "year_range with three consecutive years returns range" do
    result = year_range([2020, 2021, 2022])
    assert_equal "2020 - 2022", result
  end

  test "year_range with non-consecutive years returns comma-separated list" do
    result = year_range([2020, 2022, 2024])
    assert_equal "2020, 2022, 2024", result
  end

  test "year_range with mixed consecutive and non-consecutive years" do
    result = year_range([2020, 2021, 2023])
    assert_equal "2020 - 2021, 2023", result
  end

  test "year_range with multiple groups of consecutive years" do
    result = year_range([2018, 2019, 2020, 2022, 2023, 2025])
    assert_equal "2018 - 2020, 2022 - 2023, 2025", result
  end

  test "year_range handles unsorted years" do
    result = year_range([2020, 2021, 2022, 2023])
    assert_equal "2020 - 2023", result
  end

  test "phone_format formats US phone number" do
    result = phone_format("+14085551212")
    assert_equal "(408) 555-1212", result
  end

  test "phone_number formats for UK phone number" do
    result = phone_format("+441214960497")
    assert_equal("+44 121 496 0497", result)
  end

  # render_json_error is a controller method, not a helper method
  # It is tested in controller tests (e.g., Me::PhotosControllerTest)

  test "none_stated returns italic muted text" do
    result = none_stated
    assert_match(/None stated/, result)
    assert_match(/text-stone-muted/, result)
  end

  test "qualification amounts use short duration words and say the unit once" do
    item = Struct.new(:value, :measure)

    assert_equal "117 hr 42 min", qualification_amount("117 hours and 42 minutes")
    assert_equal "60 hr", qualification_amount("60 hours and 0 minutes")
    assert_equal "1 hr 1 min", qualification_amount("1 hour and 1 minute")
    assert_equal "15.42 credits", qualification_amount("15.42 credits")

    assert_equal "0", qualification_done(item.new("0 minutes", :hours))
    assert_equal "60", qualification_done(item.new("60 hours and 0 minutes", :hours))
    assert_equal "10 hr 17 min", qualification_done(item.new("10 hours and 17 minutes", :hours))
    assert_equal "15.42", qualification_done(item.new("15.42 credits", :credits))
    assert_equal "1", qualification_done(item.new("1 credit", :credits))
    assert_equal "0", qualification_done(item.new("zero credits", :credits))
  end

  test "the next step names the gap, when the hours must fall, and what else the same sign-ups earn" do
    item = Struct.new(:name, :needs_to_schedule, :counter)
    step = QualificationsPresenter::NextStep

    event_week = qualification_next_step(step.new(item.new(:event_week_eats, "18 hours and 0 minutes", :event_week), 1))
    assert_equal "Sign up for 18 hr more during Event Week to earn the Event Week Eat Pass and 1 more.", strip_tags(event_week)
    assert_match %r{<strong class="tabular-nums">18 hr</strong>}, event_week

    credits = qualification_next_step(step.new(item.new(:spt, "1.15 credits", :credits), 0))
    assert_equal "Sign up for 1.15 credits more to earn the Special Price Ticket.", strip_tags(credits)
  end

  test "qualification goal counts leave out the states nobody is in" do
    assert_equal "5 of 6 earned, 1 needs more sign-ups", qualification_goal_counts(earned: 5, needs_sign_ups: 1)
    assert_equal "1 of 6 earned, 3 on track, 2 need more sign-ups",
                 qualification_goal_counts(earned: 1, on_track: 3, needs_sign_ups: 2)
    assert_equal "0 of 4 earned, 4 on track", qualification_goal_counts(on_track: 4)
    assert_equal "4 of 6 earned, 1 needs more sign-ups, 1 not this year",
                 qualification_goal_counts(earned: 4, needs_sign_ups: 1, closed: 1)
  end

  # --------------------------------------------------------------- rich_text

  # Rails' default safelist has neither <s> nor <u> -- both would come back as
  # plain text -- and no table tags, and Lexxy writes all of them.
  # A live list row is rendered outside any request (PersonMessage#announce_reply),
  # where a URL's host is the renderer's example.org.
  test "photo_tag gives a photo's path in development, never a host" do
    photo = PersonPhoto.create!(person: person(:active_ranger), status: PersonPhoto::APPROVED, image_filename: "",
                                orig_filename: "", profile_filename: "p.jpg")
    photo.profile.attach(io: StringIO.new("not-really-a-jpeg"), filename: "p.jpg", content_type: "image/jpeg")
    env = Rails.method(:env)
    Rails.define_singleton_method(:env) { ActiveSupport::EnvironmentInquirer.new("development") }
    src = Nokogiri::HTML5.fragment(photo_tag(photo.profile)).at_css("img")["src"]
    assert_match %r{\A/rails/active_storage/blobs/proxy/}, src
  ensure
    Rails.define_singleton_method(:env, env) if env
  end

  test "rich_text keeps what the editor writes: strikethrough, underline, tables, list numbering" do
    html = %(<p><s>gone</s> <u>under</u> <strong>bold</strong> <em>slanted</em></p>
      <ol start="4"><li value="4">four</li></ol>
      <figure class="lexxy-content__table-wrapper"><table><tbody><tr><th>H</th><td>C</td></tr></tbody></table></figure>
      <blockquote>quoted</blockquote><pre>code</pre><hr>)

    kept = Nokogiri::HTML5.fragment(rich_text(html))

    # Asked of the parsed result, element by element: "<s" is also how <strong>
    # starts, so a search of the text would find <s> whether it was kept or not.
    %w[s u strong em ol li figure table tbody tr th td blockquote pre hr].each do |tag|
      assert kept.at_css(tag), "<#{tag}> was dropped"
    end
    assert_equal "4", kept.at_css("ol")["start"]
    assert_equal "4", kept.at_css("li")["value"]
    assert_equal "lexxy-content__table-wrapper", kept.at_css("figure")["class"]
  end

  # A merged cell without its span is an ordinary cell, and the ones beside it
  # slide into the wrong columns.
  test "rich_text keeps a merged table cell merged" do
    kept = Nokogiri::HTML5.fragment(rich_text(
      %(<table><tbody><tr><th colspan="3">Monday</th></tr><tr><td rowspan="2">Dirt</td><td>06:00</td><td>Hubcap</td></tr></tbody></table>)
    ))

    assert_equal "3", kept.at_css("th")["colspan"]
    assert_equal "2", kept.at_css("td")["rowspan"]
  end

  test "rich_text drops what could run in a reader's page" do
    result = rich_text(%(<p onclick="steal()">Hi <a href="javascript:steal()">link</a> <a href="https://example.com">ok</a></p>
      <script>steal()</script><img src="x" onerror="steal()"><p style="position: fixed">styled</p>))

    assert_no_match(/script|onclick|onerror|javascript:|style=/, result)
    assert_includes result, 'href="https://example.com"'
    assert_includes result, "styled"
  end

  # Review finding 8: a class from the app's own utilities let a message cover
  # the reader's whole screen with a page of its own.
  test "rich_text keeps only the classes Lexxy writes" do
    kept = Nokogiri::HTML5.fragment(rich_text(
      %(<p class="fixed inset-0 z-50 bg-base-100 p-8 lexxy-content__bold">Session expired.
        <a href="https://example.com/login" class="btn btn-primary">Sign in</a></p><div class="horizontal-divider"><hr></div>)
    ))

    assert_equal "lexxy-content__bold", kept.at_css("p")["class"]
    assert_nil kept.at_css("a")["class"]
    assert_equal "https://example.com/login", kept.at_css("a")["href"]
    assert_equal "horizontal-divider", kept.at_css("div")["class"]
  end

  test "rich_text says nothing for text that was never written" do
    assert_equal "", rich_text(nil).to_s
    assert_equal "", rich_text("").to_s
  end
end
