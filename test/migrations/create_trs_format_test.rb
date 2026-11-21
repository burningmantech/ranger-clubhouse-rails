# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261120000003_create_trs_format.rb")

# The seed of the trs_format table is the vendor's three import templates, and
# the export must read the same the day the constants in TrsExport became rows.
# The header rows are pinned here byte for byte, written out independently of
# the migration: the literal &amp;, the out-of-order dates, the double space in
# "Setup Access Pass  8/15", and the "Method of"/"Method Of" case difference
# all mirror the vendor template.
class CreateTrsFormatTest < ActiveSupport::TestCase
  setup do
    TrsFormat.delete_all
    CreateTrsFormat.new.send(:seed)
  end

  def header_row(slug)
    CsvExportConcern.build([TrsFormat.find_by!(slug:).headers])
  end

  test "the paid and gift ticket format header is byte-exact" do
    expected = "First Name,Last Name,Email,Question: Method Of Delivery:,Question: Nickname/Project:," \
               "Question: Notes:,Request: $250 Ticket,Request: $165 Vehicle Pass,Request: Gift Ticket," \
               "Request: Gift Vehicle Pass,Request: Transferrable $250 Ticket," \
               "Request: Transferrable $165 Vehicle Pass,Request: Transferrable Gift Ticket," \
               "Request: Transferrable Gift Vehicle Pass,Request: Transferrable $75 Vehicle Pass," \
               "Request: $75 Vehicle Pass"

    assert_equal expected, header_row("paid")
  end

  test "the unpaid format header is byte-exact" do
    sap_days = %w[8/26 8/27 8/28 8/29 8/8 8/9 8/10 8/11 8/12 8/13 8/14]
                 .map { |day| "Request: Setup Access Pass #{day} &amp; Later" }
    sap_days << "Request: Setup Access Pass  8/15 &amp; Later"
    sap_days += %w[8/16 8/17 8/18 8/19 8/20 8/21 8/22 8/23 8/24 8/25]
                  .map { |day| "Request: Setup Access Pass #{day} &amp; Later" }
    sc_days = %w[8/14 8/13 8/26 8/27 8/28 8/29 8/8 8/9 8/10 8/11 8/12 8/15 8/16 8/17 8/18 8/19 8/20 8/21 8/22 8/23 8/24]
                .map { |day| "Request: Staff Credential Pickup #{day} &amp; After" }

    expected = ["First Name", "Last Name", "Email", "Question: Method of Delivery:",
                "Question: Nickname/Project:", "Question: Notes:", "Request: Gift Vehicle Pass",
                *sap_days, "Request: Setup Access Pass - Anytime",
                *sc_days, "Request: Staff Credential Pickup Anytime",
                "Request: Staff Credential Pickup 8/25 &amp; After"].join(",")

    assert_equal expected, header_row("unpaid")
  end

  test "the lsd format header is byte-exact" do
    expected = "First Name,Last Name,Email,Question: Method Of Delivery:,Question: Nickname/Project:," \
               "Question: Notes:,Shipping Address:: Country,Shipping Address:: Full Name," \
               "Shipping Address:: Address,Shipping Address:: Address Line 2,Shipping Address:: City," \
               "Shipping Address:: State,Shipping Address:: Zip,Shipping Address:: Phone," \
               "Request: $165 Vehicle Pass - Directed,Request: $550 Ticket - Directed," \
               "Request: $675 Ticket - Directed,Request: $775 Ticket - Directed," \
               "Request: $975 Ticket - Directed,Request: $1500 Ticket - Directed," \
               "Request: $3000 Ticket - Directed,Request: Non-Transferrable $550 Ticket"

    assert_equal expected, header_row("lsd")
  end

  test "the sources are the keys the constants filled, and the placeholders are unused" do
    fields = %w[first_name last_name email delivery_type project_name note]
    days = ->(list) { list.map { |day| format("%02d%02d", *day.split("/").map(&:to_i)) } }
    sap = days.call(%w[8/26 8/27 8/28 8/29] + (8..25).map { |day| "8/#{day}" }).map { |day| "sap_#{day}" }
    sc = days.call(%w[8/14 8/13 8/26 8/27 8/28 8/29 8/8 8/9 8/10 8/11 8/12] + (15..24).map { |day| "8/#{day}" })
             .map { |day| "sc_#{day}" }

    assert_equal fields + %w[spt gift_vp gift_ticket sp_vp], TrsFormat.find_by!(slug: "paid").sources
    assert_equal fields + ["gift_vp", *sap, "sap_anytime", *sc, "sc_anytime", "sc_0825"],
                 TrsFormat.find_by!(slug: "unpaid").sources
    assert_equal fields + %w[lsd_vp lsd], TrsFormat.find_by!(slug: "lsd").sources
    assert_equal [6, 0, 14], TrsFormat.in_order.map { |format| format.columns.size - format.sources.size }
  end

  test "a seeded row is valid and does not read as changed when loaded" do
    formats = TrsFormat.in_order

    assert_equal %w[paid unpaid lsd], formats.map(&:slug)
    formats.each do |format|
      assert format.valid?, "#{format.slug}: #{format.errors.full_messages.join(' ')}"
      assert_not format.changed?, "#{format.slug} is spelled differently from how the app writes it"
    end
  end
end
