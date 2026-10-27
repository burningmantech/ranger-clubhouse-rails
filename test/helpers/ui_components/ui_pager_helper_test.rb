# frozen_string_literal: true

require "test_helper"

class UiPagerHelperTest < ActionView::TestCase
  include UiComponents::UiPagerHelper
  include ButtonHelper
  include Pagy::Method

  # Three people, two to a page: page 1 has a row past it, page 2 does not.
  def countless(page)
    people = Person.where(id: [person(:active_ranger), person(:inactive_ranger), person(:auditor_ranger)])
    pagy(:countless, people.order(:id), page:, limit: 2, request: { params: {} }).first
  end

  test "counts the pages and links the pages either side" do
    render html: ui_pager({ total: 640, total_pages: 7, page: 2 }, noun: "message") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 2 of 7 · 640 messages"
    assert_select "a[href='/log?page=1']", text: "Previous Page"
    assert_select "a[href='/log?page=3']", text: "Next Page"
  end

  test "writes thousands with commas, and one row in the singular" do
    render html: ui_pager({ total: 123_456, total_pages: 1235, page: 1000 }, noun: "request") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 1,000 of 1,235 · 123,456 requests"

    render html: ui_pager({ total: 1, total_pages: 1, page: 1 }, noun: "request") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 1 of 1 · 1 request"
  end

  test "an estimated total follows has_next_page, not the page arithmetic" do
    meta = { total: 1234, total_pages: 13, page: 12, has_previous_page: true, has_next_page: false }

    render html: ui_pager(meta, summary: "Page 12", class: "my-3") { |page| "/log?page=#{page}" }

    assert_select "div.my-3 > p", text: "Page 12"
    assert_select "a[href='/log?page=11']", text: "Previous Page"
    assert_select "a", text: "Next Page", count: 0
    assert_select "button[disabled]", text: "Next Page"
  end

  test "reads an offset Pagy object as it reads the numbers" do
    render html: ui_pager(Pagy::Offset.new(count: 640, page: 2, limit: 100), noun: "message") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 2 of 7 · 640 messages"
    assert_select "a[href='/log?page=1']", text: "Previous Page"
    assert_select "a[href='/log?page=3']", text: "Next Page"
  end

  test "an offset Pagy object with no rows reads one empty page, both buttons disabled" do
    render html: ui_pager(Pagy::Offset.new(count: 0, page: 1, limit: 50), noun: "request") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 1 of 1 · 0 requests"
    assert_select "a", count: 0
    assert_select "button[disabled]", count: 2
  end

  test "a countless Pagy object links Next only while a row lies past the page" do
    render html: ui_pager(countless(1), summary: "Page 1") { |page| "/log?page=#{page}" }

    assert_select "p", text: "Page 1"
    assert_select "button[disabled]", text: "Previous Page"
    assert_select "a[href='/log?page=2']", text: "Next Page"

    render html: ui_pager(countless(2), summary: "Page 2") { |page| "/log?page=#{page}" }

    assert_select "a[href='/log?page=1']", text: "Previous Page"
    assert_select "button[disabled]", text: "Next Page"
  end

  test "a countless Pagy object has no total for noun: to count" do
    assert_raises(ArgumentError) { ui_pager(countless(2), noun: "person") { |page| "/log?page=#{page}" } }
  end
end
