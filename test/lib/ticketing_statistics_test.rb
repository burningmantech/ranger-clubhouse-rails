# frozen_string_literal: true

require "test_helper"

# Exercises TicketingStatistics.execute, the counts behind Ticketing >
# Statistics: which people land in each headline bucket, how a type's documents
# divide across the claim pipeline, and who counts as holding provisions.
#
# The module reads the whole access_document and provision tables and the shared
# fixtures belong to other suites, so every test starts from empty tables and
# builds exactly the records it needs.
class TicketingStatisticsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
    AccessDocument.delete_all
    Provision.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- headline people counts ----------------------------------------------

  test "the headline counts describe people, not documents" do
    holder = person(:active_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(holder, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED)

    assert_equal 1, people[:claimed], "one person holding two claimed tickets is still one person"
  end

  test "only regular tickets feed the headline counts" do
    document(person(:active_ranger), type: AccessDocument::GIFT, status: AccessDocument::CLAIMED)
    document(person(:inactive_ranger), type: AccessDocument::SPT, status: AccessDocument::CLAIMED)

    assert_equal 1, people[:claimed], "a claimed gift ticket is not a claimed regular ticket"
  end

  # Banked means "banked and settled nothing else", so a claimed document of any
  # type at all takes its holder back out of the count.
  test "a person holding anything claimed is not counted as banked" do
    settled = person(:active_ranger)
    document(settled, type: AccessDocument::SPT, status: AccessDocument::BANKED)
    document(settled, type: AccessDocument::GIFT, status: AccessDocument::CLAIMED)

    banker = person(:inactive_ranger)
    document(banker, type: AccessDocument::SPT, status: AccessDocument::BANKED)

    assert_equal 1, people[:banked]
    assert_equal 0, people[:claimed], "the gift ticket holder still has no claimed regular ticket"
  end

  test "a person holding anything claimed or banked is not counted as unclaimed" do
    waiting = person(:active_ranger)
    document(waiting, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)

    part_way = person(:inactive_ranger)
    document(part_way, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    document(part_way, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED)

    assert_equal 1, people[:unclaimed]
  end

  test "submitted counts every person with a regular ticket at the vendor" do
    document(person(:active_ranger), type: AccessDocument::SPT, status: AccessDocument::SUBMITTED)
    document(person(:inactive_ranger), type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::SUBMITTED)

    assert_equal 2, people[:submitted]
  end

  # --- per-type counts ------------------------------------------------------

  test "each type counts its own documents in each status" do
    holder = person(:active_ranger)
    2.times { document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED) }
    document(holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    document(holder, type: AccessDocument::GIFT, status: AccessDocument::CLAIMED)

    spt = type_named("Special Price Tickets")
    assert_equal 2, spt.counts[AccessDocument::CLAIMED]
    assert_equal 1, spt.counts[AccessDocument::QUALIFIED]
    assert_equal 3, spt.total, "the gift ticket belongs to its own card"
  end

  test "only bankable types report a banked count" do
    assert type_named("Special Price Tickets").counts.key?(AccessDocument::BANKED)
    assert type_named("Staff Credentials").counts.key?(AccessDocument::BANKED)
    assert_not type_named("Gift Tickets").counts.key?(AccessDocument::BANKED)
    assert_not type_named("Setup Access Passes").counts.key?(AccessDocument::BANKED)
  end

  test "documents ignored by the report do not reach any card" do
    holder = person(:active_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::USED)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CANCELLED)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::TURNED_DOWN)

    assert_equal 0, type_named("Special Price Tickets").total
  end

  # --- meter geometry -------------------------------------------------------

  test "segments carry a percentage of the type total and skip empty statuses" do
    holder = person(:active_ranger)
    3.times { document(holder, type: AccessDocument::GIFT, status: AccessDocument::CLAIMED) }
    document(holder, type: AccessDocument::GIFT, status: AccessDocument::QUALIFIED)

    segments = type_named("Gift Tickets").segments

    assert_equal [[AccessDocument::CLAIMED, 75.0], [AccessDocument::QUALIFIED, 25.0]], segments
    assert_equal 100.0, segments.sum(&:last)
  end

  test "a type holding nothing has no segments and does not divide by zero" do
    empty = type_named("LSD Tickets")

    assert_equal 0, empty.total
    assert_empty empty.segments
  end

  # --- significant other setup access passes --------------------------------

  test "significant other passes count both the passes and the people holding them" do
    holder = person(:active_ranger)
    2.times { document(holder, type: AccessDocument::SAPSO, status: AccessDocument::CLAIMED) }
    document(person(:inactive_ranger), type: AccessDocument::SAPSO, status: AccessDocument::SUBMITTED)

    sapso = TicketingStatistics.execute[:sapso]
    assert_equal 2, sapso[:claimed]
    assert_equal 1, sapso[:people], "two passes for one person is still one person"
    assert_equal 1, sapso[:submitted]
  end

  # --- provisions -----------------------------------------------------------

  test "earned and allocated provisions count their holders separately" do
    provision_for(person(:active_ranger))
    provision_for(person(:inactive_ranger), is_allocated: true)
    provision_for(person(:retired_ranger), is_allocated: true, status: Provision::SUBMITTED)

    provisions = TicketingStatistics.execute[:provisions]
    assert_equal 1, provisions[:earned]
    assert_equal 2, provisions[:allocated], "a submitted allocation is still an allocation"
  end

  test "both counts people holding an earned and an allocated provision at once" do
    mixed = person(:active_ranger)
    provision_for(mixed)
    provision_for(mixed, is_allocated: true)

    provision_for(person(:inactive_ranger))

    assert_equal 1, TicketingStatistics.execute[:provisions][:both]
  end

  test "spent provisions do not make someone count as holding both" do
    spent = person(:active_ranger)
    provision_for(spent)
    provision_for(spent, is_allocated: true, status: Provision::EXPIRED)

    assert_equal 0, TicketingStatistics.execute[:provisions][:both]
  end

  test "banked provisions count their holders" do
    provision_for(person(:active_ranger), status: Provision::BANKED)
    provision_for(person(:active_ranger), status: Provision::BANKED)

    assert_equal 1, TicketingStatistics.execute[:provisions][:banked]
  end

  private

  def people
    TicketingStatistics.execute[:people]
  end

  def type_named(label)
    TicketingStatistics.execute[:types].find { |count| count.label == label } ||
      raise(ArgumentError, "no card labelled #{label.inspect}")
  end
end
