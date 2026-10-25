# frozen_string_literal: true

require "test_helper"

class MailLogTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  # An id the way SES writes them.
  SES_ID = "0100018f2b6c1a2e-1c7d9a3f-6b2e-4f0a-9a1b-2c3d4e5f6a7b-000000"

  setup do
    MailLog.delete_all
    @person = person(:active_ranger)
    @sender = person(:auditor_ranger)
  end

  # Searching by subject joins the broadcast table, which has columns of the
  # same names as mail_log. Each filter works alone whether or not the columns
  # are written with their table, so only the combinations catch a bare one.
  test "every filter combination builds valid sql" do
    create_log(subject: "Training update")

    combinations = [
      { person_id: @person.id, subject: "Training" },
      { year: Current.year, subject: "Training" },
      { email: "volunteer", subject: "Training" },
      { person_id: @person.id, year: Current.year, email: "volunteer", subject: "Training" }
    ]

    combinations.each do |query|
      result = MailLog.find_for_query(query.merge(page: 1))

      assert_equal 1, result[:meta][:total], "expected a match for #{query.keys.join(' + ')}"
    end
  end

  test "a subject search finds a message whose subject lives on its broadcast" do
    broadcast = Broadcast.create!(sender_id: @person.id, alert_id: 1, subject: "Burn night muster",
                                 email_message: "Muster at 6")
    create_log(subject: nil, broadcast_id: broadcast.id)
    create_log(subject: "Password reset")

    result = MailLog.find_for_query(subject: "muster", page: 1)

    assert_equal 1, result[:meta][:total]
    assert_equal "Burn night muster", result[:mail_log].first.subject
  end

  test "a wildcard typed into a search is matched literally" do
    create_log(subject: "100% cotton shirts")
    create_log(subject: "1000 sure things")

    result = MailLog.find_for_query(subject: "100%", page: 1)

    assert_equal 1, result[:meta][:total]
    assert_equal "100% cotton shirts", result[:mail_log].first.subject
  end

  # A page number arrives straight from a query string, where it can be
  # anything. Every one of these used to reach the database and fail there.
  test "an unusable page number falls back to a real page" do
    create_log(subject: "Only message")

    ["99999999999999999999", ["2"], "abc", "-5", "", nil, 0].each do |value|
      result = MailLog.find_for_query(page: value)

      assert_equal 1, result[:meta][:page], "expected page 1 for #{value.inspect}"
      assert_equal 1, result[:mail_log].to_a.size, "expected the message for #{value.inspect}"
    end
  end

  # created_at only keeps whole seconds and mail is written in bursts, so
  # without a second sort key the order inside a burst is undefined and a
  # message can land on two pages while another lands on none.
  test "messages sharing a timestamp are ordered the same way every time" do
    stamp = Time.current
    ids = 6.times.map { |i| create_log(subject: "Burst #{i}").id }

    MailLog.update_all(created_at: stamp)

    pages = 3.times.map { |i| MailLog.find_for_query(page: i + 1, page_size: 2)[:mail_log].map(&:id) }

    assert_equal ids.sort.reverse, pages.flatten
    assert_equal 6, pages.flatten.uniq.size, "a message appeared on more than one page"
  end

  # The list carries a whole page of rows, so it leaves the largest column
  # behind. Reading it would raise rather than quietly return nothing.
  test "the listing does not load message bodies" do
    create_log(subject: "Has a body", body: "The message body")

    row = MailLog.find_for_query(page: 1)[:mail_log].first

    assert_equal "Has a body", row.subject
    assert_raises(ActiveModel::MissingAttributeError) { row.body }
  end

  # The cutoff is six months back from a day with no counterpart that far
  # earlier. Counting back a plain thirty days a month lands in March instead of
  # February and takes messages that are still inside the window.
  test "purge_old keeps a message that is not yet six months old" do
    travel_to Time.zone.local(2027, 8, 31, 12, 0, 0) do
      keep = create_log(subject: "Recent enough", created_at: Time.zone.local(2027, 3, 1, 12, 0, 0))
      purge = create_log(subject: "Long past", created_at: Time.zone.local(2027, 1, 1, 12, 0, 0))

      assert_equal 1, MailLog.purge_old

      assert MailLog.exists?(keep.id)
      assert_not MailLog.exists?(purge.id)
    end
  end

  # The third stat box counts what the table is meant to hold: the window the
  # nightly cleanup keeps. A calendar year is longer than that window from July
  # on, and in February it would leave out last autumn's messages.
  test "retrieve_stats counts the retention window, across the turn of the year" do
    travel_to Time.zone.local(2027, 2, 15, 12, 0, 0) do
      create_log(subject: "Today", created_at: 1.hour.ago)
      create_log(subject: "Last week", created_at: 5.days.ago)
      create_log(subject: "Last autumn", created_at: Time.zone.local(2026, 9, 1, 12, 0, 0))
      create_log(subject: "Not purged yet", created_at: Time.zone.local(2026, 8, 1, 12, 0, 0))

      assert_equal({ last_24: 1, week: 2, retained: 3 }, MailLog.retrieve_stats(nil))
    end
  end

  # An SES report names one address and the id SES gave the email, so a
  # message to two addresses has to leave a row for each, both under that id.
  # Each row belongs to whoever holds its address.
  test "record_delivery writes a row for each To address under the id SES gave the email" do
    message = sent_message(to: [@person.email, "Second Ranger <second@example.com>"])
    rows = MailLog.record_delivery(message, sender_id: @sender.id)

    assert_equal MailLog.order(:id).to_a, rows
    assert_equal [@person.email, "second@example.com"], rows.map(&:to_email)
    assert_equal [@person.id, nil], rows.map(&:person_id)
    rows.map(&:reload).each do |row|
      assert_equal SES_ID, row.message_id
      assert_equal "Your shift tomorrow", row.subject
      assert_equal "<p>See you there.</p>", row.body
      assert_equal @sender.id, row.sender_id
    end
  end

  test "a report naming one address of a two-address email stamps only that address's row" do
    first, second = MailLog.record_delivery(sent_message, sender_id: @sender.id)

    assert_equal second, MailLog.mark_as_bounced("second@example.com", SES_ID)
    assert second.reload.did_bounce
    assert_not first.reload.did_bounce

    MailLog.mark_as_delivered("first@example.com", SES_ID)

    assert_not_nil first.reload.delivered_at
    assert_nil second.reload.delivered_at
  end

  # SMTP and the test adapter set no SES header.
  test "a message sent without SES keeps the mail gem's Message-ID" do
    MailLog.record_delivery(sent_message(ses_id: nil), sender_id: @sender.id)

    assert_equal ["gem-id@example.com"], MailLog.pluck(:message_id).uniq
  end

  test "a message with no To address writes no row" do
    assert_no_difference "MailLog.count" do
      rows = MailLog.record_delivery(sent_message(to: nil), sender_id: @sender.id)

      assert_empty rows
    end
  end

  # person.email is unique whatever its case, and an address saved before
  # Person downcased it can still be in mixed case. The string form of
  # update_all writes it past normalizes, which would downcase it.
  test "a row belongs to whoever holds its address, whatever the case of either" do
    Person.where(id: @person.id).update_all("email = 'Mixed.Case@Example.com'")

    row, = MailLog.record_delivery(sent_message(to: ["mixed.case@EXAMPLE.com"]), sender_id: @sender.id)

    assert_equal @person.id, row.person_id
    assert_equal "mixed.case@EXAMPLE.com", row.to_email
  end

  test "an address nobody holds leaves the row without a person" do
    row, = MailLog.record_delivery(sent_message(to: ["nobody@example.com"]), sender_id: @sender.id)

    assert_nil row.person_id
  end

  # A team or cadre list belongs to no one, and is never looked up -- even when
  # an account happens to hold the address.
  test "a mailing list address gets no person" do
    Person.where(id: @person.id).update_all("email = 'ranger-shiny-list@burningman.org'")

    row, = assert_no_queries_match(/FROM `person`/) do
      MailLog.record_delivery(sent_message(to: ["ranger-shiny-list@burningman.org"]), sender_id: @sender.id)
    end

    assert_nil row.person_id
  end

  test "every To address is looked up in one query" do
    message = sent_message(to: [@person.email, @sender.email, "nobody@example.com"])

    rows = assert_queries_match(/FROM `person`/, count: 1) do
      MailLog.record_delivery(message, sender_id: nil)
    end

    assert_equal [@person.id, @sender.id, nil], rows.map(&:person_id)
  end

  test "an applicant's email keeps its application" do
    application = prospective_application(:pending_qualified)

    row, = MailLog.record_delivery(sent_message, sender_id: @sender.id, prospective_application_id: application.id)

    assert_equal application.id, row.prospective_application_id
  end

  # The five mailers whose email carries a sign-in secret or a private message
  # keep everything but the text: the column keeps its NULL.
  test "a withheld body is left out of the row and nothing else is" do
    row, = MailLog.record_delivery(sent_message(to: [@person.email]), sender_id: @sender.id, withhold_body: true)

    assert_nil MailLog.where(id: row.id).pick(:body)
    row = MailLog.find(row.id)
    assert row.body_withheld?
    assert_equal ["Your shift tomorrow", @sender.id, @person.id, SES_ID],
                 [row.subject, row.sender_id, row.person_id, row.message_id]
  end

  test "a body that was kept, even an empty one, is not withheld" do
    row, = MailLog.record_delivery(sent_message, sender_id: @sender.id)
    empty = create_log(subject: "Empty body", body: "")

    assert_not MailLog.find(row.id).body_withheld?
    assert_equal "", MailLog.where(id: empty.id).pick(:body)
    assert_not MailLog.find(empty.id).body_withheld?
  end

  # A broadcast's rows hold no body of their own: they read the broadcast's.
  test "a broadcast's row is not withheld" do
    broadcast = Broadcast.create!(sender_id: @person.id, alert_id: 1, subject: "Muster", email_message: "Muster at 6")
    MailLog.record_ses_sends([{ person_id: @person.id, to_email: @person.email, message_id: SES_ID }],
                             sender_id: @sender.id, from_email: "do-not-reply@burningman.org",
                             broadcast_id: broadcast.id)
    row = MailLog.find_by!(broadcast_id: broadcast.id)

    assert_nil MailLog.where(id: row.id).pick(:body)
    assert_not row.body_withheld?
  end

  test "a row listed without its body cannot say whether the body was withheld" do
    create_log(subject: "Listed")

    row = MailLog.find_for_query(page: 1)[:mail_log].first

    assert_raises(ActiveModel::MissingAttributeError) { row.body_withheld? }
  end

  # The email has gone by the time its rows are written, and the database
  # refuses a subject longer than its column, so the row keeps it cut.
  test "a subject longer than its column is cut to fit, ending in an ellipsis" do
    rows = MailLog.record_delivery(sent_message(subject: "x" * 300), sender_id: @sender.id)

    assert_equal 2, rows.size
    rows.map(&:reload).each do |row|
      assert_equal "#{"x" * 252}...", row.subject
      assert_equal 255, row.subject.length
    end
  end

  # utf8mb4 counts a varchar in characters, not bytes, and so does the cut.
  test "a long subject is cut by characters, not bytes" do
    rows = MailLog.record_delivery(sent_message(subject: "🔥" * 300), sender_id: @sender.id)

    assert_equal 2, rows.size
    rows.map(&:reload).each do |row|
      assert_equal "#{"🔥" * 252}...", row.subject
      assert_equal 255, row.subject.length
      assert_equal 1_011, row.subject.bytesize
    end
  end

  # normalizes leaves nil alone, so a message with no subject keeps its NULL.
  test "a subject that fits, or none at all, is kept as it is" do
    assert_equal "x" * 255, MailLog.normalize_value_for(:subject, "x" * 255)
    assert_nil MailLog.normalize_value_for(:subject, nil)
  end

  private

  # A message as deliver_now hands it back, carrying the header the :ses_mail
  # delivery method sets. The second recipient has a name in front, which the
  # row leaves out: SES's reports name the bare address.
  def sent_message(to: ["first@example.com", "Second Ranger <second@example.com>"], ses_id: SES_ID,
                   subject: "Your shift tomorrow")
    message = Mail.new(from: "do-not-reply@burningman.org", to:, subject:,
                       message_id: "<gem-id@example.com>", body: "<p>See you there.</p>")
    message.header[:ses_message_id] = ses_id if ses_id
    message
  end

  def create_log(subject:, body: "Plain body", broadcast_id: nil, created_at: nil)
    MailLog.create!(
      person_id: @person.id,
      broadcast_id: broadcast_id,
      from_email: "do-not-reply@burningman.org",
      to_email: "volunteer@example.com",
      message_id: "msg-#{SecureRandom.hex(8)}",
      subject: subject,
      body: body,
      created_at: created_at
    )
  end
end
