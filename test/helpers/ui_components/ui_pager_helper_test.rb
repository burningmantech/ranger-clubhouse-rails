# frozen_string_literal: true

require "test_helper"

class UiPagerHelperTest < ActionView::TestCase
  include UiComponents::UiPagerHelper
  include ButtonHelper

  test "counts the pages and links the pages either side" do
    render html: ui_pager({ total: 640, total_pages: 7, page: 2 }, noun: "message") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 2 of 7 · 640 messages"
    assert_select "a[href='/log?page=1']", text: "Previous Page"
    assert_select "a[href='/log?page=3']", text: "Next Page"
  end

  test "an estimated total follows has_next_page, not the page arithmetic" do
    meta = { total: 1234, total_pages: 13, page: 12, has_previous_page: true, has_next_page: false }

    render html: ui_pager(meta, summary: "Page 12", class: "my-3") { |page| "/log?page=#{page}" }

    assert_select "div.my-3 > p", text: "Page 12"
    assert_select "a[href='/log?page=11']", text: "Previous Page"
    assert_select "a", text: "Next Page", count: 0
    assert_select "button[disabled]", text: "Next Page"
  end
end
