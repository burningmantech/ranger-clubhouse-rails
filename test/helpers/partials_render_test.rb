# frozen_string_literal: true

require "test_helper"

# Partials no controller test reaches: their pages need state the suite never
# builds (vehicle eligibility, a live Moodle lookup, the timesheet-correction
# window). Rendering them here proves each branch renders, and gives
# bin/css_check a snapshot of it.
class PartialsRenderTest < ActionView::TestCase
  include ApplicationController._helpers

  test "eligible positions lists each qualifying position" do
    positions = [Struct.new(:title).new("Green Dot"), Struct.new(:title).new("Sandman")]

    render partial: "me/vehicles_dashboard/eligible_positions",
           locals: { full_name: "Personal Vehicle Request", name: "PVR", positions: }

    assert_select "li", text: "Sandman"
  end

  # Stands in for VehicleDashboard, answering what the PVR partials ask. As in the
  # model, positions to sign up for are listed only to a Ranger who holds one but
  # isn't eligible.
  PvrDashboard = Data.define(:pvr_eligible?, :pvr_potential?, :personal_vehicle_agreement_signed?, :mvr_approved?,
                             :pvr_eligible_positions, :vehicles) do
    def self.for(eligible: false, potential: false, signed: false, mvr_approved: true)
      positions = !eligible && potential ? [Struct.new(:title).new("Green Dot")] : []
      new(eligible, potential, signed, mvr_approved, positions, [])
    end
  end

  test "the PVR section's header badge names each state its body shows" do
    # The partials render theirs by bare name, resolved against the controller's path: "" in a view test.
    controller.controller_path = "me/vehicles_dashboard"

    { "action needed" => [PvrDashboard.for(potential: true), "Agreement Required"],
      "pending" => [PvrDashboard.for(eligible: true, mvr_approved: false), "MVR Approval Required First"],
      "eligible to submit" => [PvrDashboard.for(eligible: true, signed: true), "New Vehicle Request"],
      "not yet eligible" => [PvrDashboard.for(potential: true, signed: true), "Not Yet Eligible"],
      "not permitted" => [PvrDashboard.for(signed: true), "Not Authorized"] }.each do |word, (dashboard, body)|
      render partial: "me/vehicles_dashboard/pvr_info", locals: { dashboard: }

      assert_select "[role=heading] .badge", text: word
      assert_includes rendered, body
    end
  end

  test "a Ranger who holds a PVR position but isn't eligible reads not yet eligible, once" do
    # The partials render theirs by bare name, resolved against the controller's path: "" in a view test.
    controller.controller_path = "me/vehicles_dashboard"

    render partial: "me/vehicles_dashboard/pvr_info",
           locals: { dashboard: PvrDashboard.for(potential: true, signed: true) }

    assert_select "[role=heading] .badge.badge-warning", text: "not yet eligible"
    assert_select ".badge", count: 1
    assert_not_includes rendered, "eligible to submit"
  end

  test "moodle account renders every shape" do
    person = person(:active_ranger)
    fields = [{ label: "Email", actual: "a@example.com", expected: "a@example.com", in_sync: true },
              { label: "Callsign", actual: "old", expected: "new", in_sync: false }]

    accounts = [{ status: :not_setup }, { status: :missing_account, lms_id: 42 },
                { status: :success, in_sync: true, fields: fields.first(1) },
                { status: :success, in_sync: false, fields: }]
    render partial: "person/training/moodle_account", collection: accounts, as: :account, locals: { person: }

    assert_match "No Moodle user was found", rendered
  end

  test "timesheet confirm renders each stage" do
    @corrections_enabled = true
    @timesheets_unverified = 2
    @timesheets_pending = 1
    @missing_requests_pending = 1

    @have_outstanding = true
    render partial: "common/timesheet_confirm"
    @have_outstanding = false
    @final_confirmation = true
    render partial: "common/timesheet_confirm"
    @final_confirmation = false
    render partial: "common/timesheet_confirm"

    assert_match "Final Confirmation", rendered
  end

  test "status medallion renders every state and size" do
    %i[warning error success info].product(%i[md lg]).each do |state, size|
      render partial: "common/status_medallion", locals: { icon: "check", state:, size: }

      assert_select "i.fa-check", 1
    end
  end

  # Texts are queued like everything else, so what became of each is on the
  # broadcast's own page. The names come last, after that sentence.
  test "the sent callout points at the broadcast's page, then names the people no channel reaches" do
    people = [Rbs::Recipient.new(callsign: "Alone", use_sms: false, use_email: false),
              Rbs::Recipient.new(callsign: "Apart", use_sms: false, use_email: false),
              Rbs::Recipient.new(callsign: "Texted", use_sms: true, use_email: false)]
    result = Rbs::TransmitResult.new(people:, texts_queued: 1, emails_queued: 0, clubhouse_messages: 0,
                                     sent_sms: true, sent_email: true, sent_clubhouse: false)

    render partial: "common/rbs/delivery_summary",
           locals: { result:, sandboxes: [], test_address: nil, history_path: "/broadcast" }

    assert_select ".box-success a[href=?]", "/broadcast", text: "this broadcast's page"
    assert_select ".box-success", text: /this broadcast.s page\.\s+2 people on the list can.t be reached by text or email: Alone and Apart\.\s*\z/
  end

  test "a Clubhouse message reaches everyone listed, so the sent callout counts them all" do
    people = %w[Alone Apart].map { |callsign| Rbs::Recipient.new(callsign:, use_sms: false, use_email: false) }
    result = Rbs::TransmitResult.new(people:, texts_queued: 0, emails_queued: 0, clubhouse_messages: 2,
                                     sent_sms: true, sent_email: true, sent_clubhouse: true)

    render partial: "common/rbs/delivery_summary", locals: { result:, sandboxes: [], test_address: nil }

    assert_select ".box-success", text: /Broadcast sent\s+to 2 people\./
    assert_no_match "reached by text or email", rendered
  end

  # An emergency that reaches no one on its list still sends, to 0 people.
  # Callsigns are member data: the sentence is a plain String, so the page
  # escapes them.
  test "the sent callout counts 0 when no one on the list is reached, and escapes the names" do
    people = [Rbs::Recipient.new(callsign: "<b>Bold</b>", use_sms: false, use_email: false)]
    result = Rbs::TransmitResult.new(people:, texts_queued: 0, emails_queued: 0, clubhouse_messages: 0,
                                     sent_sms: true, sent_email: true, sent_clubhouse: false)

    render partial: "common/rbs/delivery_summary", locals: { result:, sandboxes: [], test_address: nil }

    assert_select ".box-success", text: /Broadcast sent\s+to 0 people\./
    assert_includes rendered, "1 person on the list can&#39;t be reached by text or email: &lt;b&gt;Bold&lt;/b&gt;."
  end

  # 251 on-site Rangers would be slow to build, and only the note is checked.
  test "the recipients table note past the cap counts only the people the broadcast reaches" do
    people = Array.new(251) do |index|
      Rbs::Recipient.new(callsign: "R#{index}", status: Person::ACTIVE, first_name: "R", last_name: index.to_s,
                         use_sms: true, use_email: true)
    end

    render partial: "communication/rbs_broadcasts/recipients_table",
           locals: { people:, sms: true, email: true, reached: 249 }

    assert_select "p", text: /callsign order\.\s+249 of them receive the broadcast\./
    assert_no_match "All 251", rendered
  end

  test "the recipients table note past the cap says all of them receive it when everyone is reached" do
    people = Array.new(251) { |index| Rbs::Recipient.new(callsign: "R#{index}", use_sms: true, use_email: true) }

    render partial: "communication/rbs_broadcasts/recipients_table",
           locals: { people:, sms: true, email: true, reached: 251 }

    assert_select "p", text: /callsign order\.\s+All 251 receive the broadcast\./
  end
end
