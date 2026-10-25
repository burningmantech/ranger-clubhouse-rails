# frozen_string_literal: true

require "test_helper"

class TableHelperTest < ActionView::TestCase
  include TableHelper

  test "renders a plain table with responsive: false" do
    render inline: <<~ERB
      <%= ui_table responsive: false, id: "inventory", class: "inventory-table" do |t| %>
        <%= t.header do %>
          <%= t.heading "Item" %>
          <%= t.heading "Count", right: true %>
        <% end %>
        <%= t.body do %>
          <%= t.row id: "row-1" do %>
            <%= t.row_header "Radio" %>
            <%= t.cell 12, right: true %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    # Capped at its parent: a fit-width box would otherwise grow with its
    # content past a phone's screen and push the whole page sideways.
    assert_select "div.table-container.w-fit.max-w-full" do
      assert_select "table#inventory.text-body.table-auto.inventory-table" do
        assert_select "thead.table-header th[scope=col]", text: "Item"
        assert_select "thead.table-header th[scope=col].text-end", text: "Count"
        assert_select "tbody tr#row-1.table-row-striped.table-row-hover" do
          assert_select "th[scope=row].table-row-header", text: "Radio"
          assert_select "td.text-end", text: "12"
        end
      end
    end
    assert_select "table.responsive-table", count: 0
  end

  test "renders a responsive table by default, as a real <table> with auto-derived data-labels" do
    render inline: <<~ERB
      <%= ui_table full_width: true,
                   striped: true,
                   caption: "Inventory",
                   id: "inventory",
                   class: "mb-3",
                   data: { testid: "inventory-table" } do |t| %>
        <%= t.header do %>
          <%= t.heading "Item", width: "200px", data: { column: "item" } %>
          <%= t.heading "Count", right: true %>
          <%= t.heading center: true do %>
            <span>Status</span>
          <% end %>
        <% end %>
        <%= t.body class: "body-extra" do %>
          <%= t.row id: "row-1", data: { testid: "inventory-row" } do %>
            <%= t.row_header "Radio" %>
            <%= t.cell 12 %>
            <%= t.cell "Ready", center: true %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "div.table-container.w-full" do
      assert_select(
        "table#inventory.text-body.table-auto.w-full.responsive-table.mb-3"
      ) do
        assert_select "caption.sr-only", text: "Inventory"
        assert_select "thead.table-header" do
          assert_select "th[scope=col][data-column=item][style*='width: 200px']", text: "Item"
          assert_select "th[scope=col].text-end", text: "Count"
          assert_select "th[scope=col].text-center span", text: "Status"
        end
        assert_select "tbody.body-extra" do
          assert_select "tr#row-1.table-row-striped.table-row-hover" do
            assert_select "th[scope=row][data-label=Item]", text: "Radio"
            assert_select "td[data-label=Count]", text: /12/
            assert_select "td[data-label=Status].text-center", text: /Ready/
          end
        end
      end
    end
    assert_includes rendered, 'data-testid="inventory-table"'
    assert_includes rendered, 'data-testid="inventory-row"'
    assert_select "[style*='grid-template-columns']", count: 0
  end

  test "a heading with an ampersand reaches data-label escaped exactly once" do
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Teams & positions" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Green Dot" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_includes rendered, 'data-label="Teams &amp; positions"'
    assert_not_includes rendered, "&amp;amp;"
  end

  test "responsive tables can opt out of full width and striped rows" do
    render inline: <<~ERB
      <%= ui_table responsive: true, full_width: false, striped: false do |t| %>
        <%= t.header do %>
          <%= t.heading "Name" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Ada" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "div.table-container.w-fit > table.responsive-table.table-auto"
    assert_select "tr.table-row-base.table-row-hover"
    assert_select "tr.table-row-striped", count: 0
  end

  test "responsive heading HTML is stripped to plain text in data-label" do
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading do %><strong>Full</strong> name<% end %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Ada Lovelace" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td[data-label='Full name']", text: "Ada Lovelace"
  end

  test "caller can override data-label via data: { label: ... }" do
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Actions" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Edit", data: { label: "Custom" } %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td[data-label=Custom]", text: "Edit"
    assert_select "td[data-label=Actions]", count: 0
  end

  test "non-responsive tables do not emit data-label attributes" do
    render inline: <<~ERB
      <%= ui_table responsive: false do |t| %>
        <%= t.header do %>
          <%= t.heading "Name" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Ada" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td", text: "Ada"
    assert_select "td[data-label]", count: 0
    assert_select "div.\\@container", count: 0
  end

  test "a cell spanning several columns never inherits the first column's mobile label" do
    # The "no matching records" line and the error under a failed row are both
    # written as one colspan cell. Labeled by index it would read
    # "Callsign: No matching records" on a phone.
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
          <%= t.heading "Status" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "No matching records", colspan: 2 %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td[colspan=2]", text: "No matching records"
    assert_select "td[data-label]", count: 0
  end

  test "cells after a spanning cell keep their own labels" do
    # The spanning cell consumes every column it covers, so the index the next
    # cell reads from is the heading actually above it.
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
          <%= t.heading "Status" %>
          <%= t.heading "Position" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Bucket", colspan: 2 %>
            <%= t.cell "Dirt" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td[data-label=Position]", text: "Dirt"
    assert_select "td[data-label=Status]", count: 0
  end

  test "an explicit label still reaches a spanning cell" do
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
          <%= t.heading "Status" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.cell "Bucket", colspan: 2, data: { label: "Person" } %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td[data-label=Person]", text: "Bucket"
  end

  test "a detail row spans every column without being told how many there are" do
    render inline: <<~ERB
      <%= ui_table do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
          <%= t.heading "Status" %>
          <%= t.heading "Why" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.row_header "Bucket" %>
            <%= t.cell "Active" %>
            <%= t.cell "toggle" %>
          <% end %>
          <%= t.detail_row id: "detail-1" do %>
            <p>Teams: Green Dot Cadre</p>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "tr#detail-1.table-detail-row" do
      assert_select "td.table-detail-cell[colspan=3]", text: /Green Dot Cadre/
    end
  end

  test "a detail row starts closed" do
    # toggle_controller opens a row by removing `hidden`, so that class is the
    # contract. The specificity fight with `.responsive-table tr` is settled in
    # tables.css, not by an important utility here.
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
        <% end %>
        <%= t.body do %>
          <%= t.detail_row id: "detail-1" do %>Why<% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "tr#detail-1.hidden[aria-hidden=true]"
  end

  test "a detail cell never inherits the first column's mobile label" do
    # Responsive labels are matched to headings by cell index; a cell spanning
    # every column would otherwise read "Callsign: ..." on a phone.
    render inline: <<~ERB
      <%= ui_table responsive: true do |t| %>
        <%= t.header do %>
          <%= t.heading "Callsign" %>
          <%= t.heading "Status" %>
        <% end %>
        <%= t.body do %>
          <%= t.row do %>
            <%= t.row_header "Bucket" %>
            <%= t.cell "Active" %>
          <% end %>
          <%= t.detail_row id: "detail-1", label: "Bucket" do %>Why<% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "th[data-label=Callsign]", text: "Bucket"
    assert_select "td.table-detail-cell[data-label]", count: 0
    # The label names the row on mobile only -- on desktop the row above it says so.
    assert_select "td.table-detail-cell div.lg\\:hidden", text: "Bucket"
  end

  test "a detail row without a label renders no naming block at all" do
    render inline: <<~ERB
      <%= ui_table do |t| %>
        <%= t.header do %><%= t.heading "Callsign" %><% end %>
        <%= t.body do %>
          <%= t.detail_row id: "detail-1" do %>Why<% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "td.table-detail-cell", text: "Why"
    assert_select "td.table-detail-cell div.lg\\:hidden", count: 0
  end

  test "a detail row honors an explicit colspan and extra attributes" do
    render inline: <<~ERB
      <%= ui_table do |t| %>
        <%= t.header do %>
          <%= t.heading "A" %>
          <%= t.heading "B" %>
        <% end %>
        <%= t.body do %>
          <%= t.detail_row id: "d", colspan: 7, class: "extra" do %>Why<% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "tr#d.table-detail-row.extra"
    assert_select "td.table-detail-cell[colspan=7]"
  end

  test "detail_row requires a block" do
    error = assert_raises(ArgumentError) do
      ui_table { |t| t.detail_row(id: "x") }
    end
    assert_match(/requires a block/, error.message)
  end

  test "rejects unknown positional arguments" do
    error = assert_raises(ArgumentError) do
      ui_table("oops") { |_| }
    end
    assert_match(/options hash/, error.message)
  end

  test "keeps legacy options hash and block-argument usage working for responsive tables" do
    render inline: <<~ERB
      <%= ui_table({ caption: "Legacy", striped: true, responsive: true }) do |t| %>
        <%= t.header do |h| %>
          <%= h.heading "Name" %>
        <% end %>
        <%= t.body do |b| %>
          <%= b.row do |r| %>
            <%= r.cell "Ada" %>
          <% end %>
        <% end %>
      <% end %>
    ERB

    assert_select "table.responsive-table" do
      assert_select "caption", text: "Legacy"
      assert_select "tr.table-row-striped" do
        assert_select "td[data-label=Name]", text: /Ada/
      end
    end
  end
end
