# frozen_string_literal: true

require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  include MessagesHelper

  test "message_list_time shows the clock today, the date otherwise, and the year once it differs" do
    today = Current.time.in_time_zone("America/Los_Angeles").change(hour: 14, min: 24)
    assert_equal "14:24", message_list_time(today)

    # A fixed day of this year that cannot be today, so the date branch is
    # exercised whatever day the suite runs.
    earlier = today.month == 6 && today.day == 15 ? today.change(month: 3, day: 1) : today.change(month: 6, day: 15)
    assert_equal earlier.strftime("%b %-d"), message_list_time(earlier)

    last_year = today - 1.year
    assert_equal last_year.strftime(DateTimeHelper::DATE), message_list_time(last_year)
  end

  test "message_search_marks marks each word from its start to its end and escapes the rest" do
    assert_equal %(&lt;b&gt;<mark class="search-hit">Dirt</mark>&lt;/b&gt; &amp; <mark class="search-hit">dirty</mark>, undirty),
                 message_search_marks("<b>Dirt</b> & dirty, undirty", "dirt the")
    # Only short words: the whole query, wherever it is.
    assert_equal %(at <mark class="search-hit">18</mark>:00), message_search_marks("at 18:00", "18")
    assert_equal "plain", message_search_marks("plain", nil)
  end

  test "message_list_snippet shows the words around a search's first match in the thread, once escaped" do
    swap = person_message(:search_dirt_swap)
    assert_equal %(Sure, I&#39;ll bring the <mark class="search-hit">thermos</mark>.), message_list_snippet(swap, "thermos")
    assert_equal %(Can you take my 18:00 <mark class="search-hit">Dirt</mark> shift? I&#39;ll take your Saturday…),
                 message_list_snippet(swap, "dirt")

    # No search, or a hit on the callsign alone: the latest message, as a folder's list shows it.
    assert_equal "Sure, I&#39;ll bring the thermos.", message_list_snippet(swap, nil)
    assert_equal "Sure, I&#39;ll bring the thermos.", message_list_snippet(swap, "AlphaN")
  end

  test "message_list_snippet reads the text of a message written in the editor, never its markup" do
    radio = person_message(:search_radio_archived)
    # The excerpt is one line: its words are joined with spaces.
    assert_equal %(Bring the <mark class="search-hit">spare</mark> batteries to the depot. Thanks!),
                 message_list_snippet(radio, "spare")
    assert_equal "Bring the spare batteries to the depot.\nThanks!", message_list_snippet(radio, nil)
  end

  test "message_search_summary counts the hits" do
    assert_equal "1 conversation matches “dirt” in every folder", message_search_summary(1, "dirt")
    assert_equal "3 conversations match “dirt” in every folder", message_search_summary(3, "dirt")
    assert_equal "No conversations match “dirt” in any folder", message_search_summary(0, "dirt")
  end
end
