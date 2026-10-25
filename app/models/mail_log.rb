# frozen_string_literal: true

class MailLog < ApplicationRecord
  self.table_name = "mail_log"

  PAGE_SIZE_DEFAULT = 50

  # How long a sent message is kept before the nightly cleanup removes it.
  RETENTION = 6.months

  # The width of the subject column.
  SUBJECT_LIMIT = 255

  # What a list of messages needs to draw a row. The compressed message body is
  # left out on purpose: it is the largest column by far, and a list would carry
  # a whole page of them to show none.
  LIST_COLUMNS = %w[
    id created_at subject from_email to_email
    sender_id person_id broadcast_id did_bounce did_complain
  ].freeze

  # Team and cadre mailing lists, which belong to no one, so a message sent to
  # one is never looked up in person: Clubhouse 2's pattern (MailSentListener).
  LIST_ADDRESS = /\Arangers?-[^@]*-(?:list|cadre|team)@(?:[^@]*\.)?burningman\.(?:com|org)\z/i

  belongs_to :broadcast, optional: true
  belongs_to :sender, class_name: "Person", optional: true
  belongs_to :person, optional: true
  belongs_to :prospective_application, optional: true

  # The email has gone by the time its rows are written, and the database
  # refuses a subject longer than its column outright, which would lose the
  # rows of an email that was sent. A cut subject ends in "..." so a reader
  # can tell; the email itself carries all of it.
  normalizes :subject, with: ->(value) { value.truncate(SUBJECT_LIMIT) }

  # Virtual attribute for computed year column
  attribute :year, :integer

  class << self
    # Record a delivered message: one row per To address, as Clubhouse 2 did,
    # so a delivery, bounce or complaint report -- which names one address --
    # stamps that recipient's row alone. A message with no To address writes
    # nothing and is read no further: the stand-in for one an action never
    # built (ActionMailer's NullMail) has no body to read.
    # ApplicationMailer#record_mail_log calls it for every email.
    #
    # Each row's person is whoever holds that To address, as in Clubhouse 2:
    # the Mail Log means mail sent to or from someone, so a message about a
    # person sent to someone else is not theirs. A mailing list address gets
    # no person. All the addresses are looked up in one query.
    #
    # withhold_body leaves the body out, so the column keeps its NULL: the
    # mailers whose email carries a sign-in secret or a private message
    # (ApplicationMailer.withhold_body_from_mail_log). See #body_withheld?.
    #
    # Mail sent through SES (the :ses_mail delivery method, SesMailDelivery,
    # once production opts in) carries the id SES gave it in the
    # ses_message_id header, set during delivery; that is the id the reports
    # name, so the rows keep it. Mail sent any other way (SMTP, the test
    # adapter) has no such header and keeps the mail gem's own Message-ID,
    # which SES would replace, so no report ever finds those rows. The message
    # is read after any test address replaced its recipients
    # (MailTestAddressInterceptor), so its rows name the test inbox.
    #
    # @return [Array<MailLog>] the rows written
    def record_delivery(message, sender_id:, withhold_body: false, prospective_application_id: nil)
      to_emails = Array(message.to)
      return [] if to_emails.empty?

      row = {
        sender_id:,
        prospective_application_id:,
        from_email: message.from&.first || "",
        message_id: message.header[:ses_message_id]&.value || message.message_id || "",
        subject: message.subject,
        was_sent: message.perform_deliveries
      }
      row[:body] = html_body(message) unless withhold_body
      people = person_ids_by_address(to_emails)

      # create!, not insert_all: insert_all skips the body= setter that
      # compresses the body.
      transaction do
        to_emails.map { |to_email| create!(**row, to_email:, person_id: people[to_email.downcase]) }
      end
    end

    # Record broadcast emails Amazon SES took through its API, where there is
    # no Mail::Message to read: one row per address, under the id SES gave
    # each email -- the id its delivery and bounce reports name. Subject and
    # body are left empty because a broadcast's rows read theirs from the
    # broadcast, which is why a broadcast is required.
    #
    # @param sent [Array<Hash>] person_id:, to_email:, message_id: for each email
    def record_ses_sends(sent, sender_id:, from_email:, broadcast_id:)
      insert_all(sent.map { |email| { **email, sender_id:, from_email:, broadcast_id:, was_sent: true } })
    end

    # HTML body of a Mail::Message (multipart or single-part).
    def html_body(message)
      (message.html_part || message).body.decoded
    end

    # Remove messages older than the retention window. Rows without a date are
    # left alone -- there is no way to tell how old they are.
    #
    # @return [Integer] how many rows were removed
    def purge_old(older_than: RETENTION)
      where(created_at: ...older_than.ago).in_batches.delete_all
    end

    private

    # Who holds each address, keyed by the address in lower case. person.email
    # is unique whatever its case, so an address finds one person at most, but
    # one stored before Person downcased it can be in mixed case. With only
    # list addresses left there is nothing to ask, and no query is made.
    def person_ids_by_address(addresses)
      Person.where(email: addresses.grep_v(LIST_ADDRESS)).pluck(:email, :id).to_h { |email, id| [email.downcase, id] }
    end
  end

  # Custom setter for body compression
  def body=(value)
    compressed = value.present? ? ActiveSupport::Gzip.compress(value) : ""
    write_attribute(:body, compressed)
  end

  # Get the subject attribute either from this record or the associated broadcast record
  def subject
    return broadcast&.subject || "" if broadcast_id.present?

    super
  end

  # Get the body attribute. Either return the associated broadcast record's
  # body attribute, or return a gunzip'ed version. Decode if the original
  # value was quoted-printable encoded.
  def body
    if broadcast_id.present?
      body_text = broadcast&.email_message || ""
    else
      # super, not read_attribute: a row fetched for a list never asked for
      # this column, and super says so instead of handing back an empty message
      # that reads as a real one.
      raw_body = super
      return "" if raw_body.blank?

      begin
        body_text = ActiveSupport::Gzip.decompress(raw_body)
      rescue Zlib::GzipFile::Error
        # If not gzipped, return raw
        return to_utf8(raw_body.to_s)
      end
    end

    # Check for quoted-printable encoding
    body_text = body_text.unpack1("M") if body_text =~ /=3d/i

    to_utf8(body_text)
  end

  # Whether this email's text was never kept: no broadcast to read it from and
  # a NULL body, as record_delivery leaves a withheld mailer's row. Every other
  # writer stores a string, "" for an empty body. Like #body, it raises on a
  # row fetched without the column (LIST_COLUMNS) -- self[] does -- rather
  # than read the missing column as withheld.
  def body_withheld?
    broadcast_id.nil? && self[:body].nil?
  end

  private

  # Gunzip output and the raw binary column bytes come back BINARY-encoded;
  # present them as UTF-8 (scrubbed) so views can render them.
  def to_utf8(text)
    text.dup.force_encoding(Encoding::UTF_8).scrub
  end

  class << self
    include Pagy::Method

    # Retrieve mail log records based on the given criteria
    #
    # @param query [Hash] Query parameters
    #   - person_id: specific person (matches sender_id or person_id)
    #   - year: specific year
    #   - email: partial email address (matches to_email or from_email)
    #   - subject: partial subject line
    #   - page: page number (1 to n)
    #   - page_size: size of page (default: PAGE_SIZE_DEFAULT)
    #
    # @return [Hash] { mail_log:, meta: { total:, total_pages:, page_size:, page: } }
    # Every column below is written with its table name. Searching by subject
    # joins the broadcast table, which carries columns of the same names
    # (created_at, sender_id), and an unqualified one is an error the database
    # only raises once the two filters are used together.
    def find_for_query(query)
      scope = includes(:person, :sender, :broadcast).select(LIST_COLUMNS)

      if query[:person_id].present?
        scope = scope.where("mail_log.person_id = :id OR mail_log.sender_id = :id", id: query[:person_id])
      end

      scope = scope.where_year("mail_log.created_at", query[:year]) if query[:year].present?

      if query[:email].present?
        term = "%#{sanitize_sql_like(query[:email])}%"
        scope = scope.where("mail_log.to_email LIKE :term OR mail_log.from_email LIKE :term", term:)
      end

      # A message sent to a group keeps its subject on the broadcast record
      # rather than on its own row, so both places have to be searched for
      # those messages to turn up.
      if query[:subject].present?
        term = "%#{sanitize_sql_like(query[:subject])}%"
        scope = scope.left_joins(:broadcast)
                     .where("mail_log.subject LIKE :term OR broadcast.subject LIKE :term", term:)
      end

      # Messages are written in bursts and the timestamp only keeps whole
      # seconds, so the id breaks ties. Without it the order within a second is
      # undefined, and a message could sit on two pages at once while another
      # never appears on any.
      scope = scope.order(created_at: :desc, id: :desc)

      page_size = to_page_number(query[:page_size], PAGE_SIZE_DEFAULT)
      total = scope.count(:all)
      last_page = [(total.to_f / page_size).ceil, 1].max
      # Held to a page that exists. A bookmarked or hand-typed number would
      # otherwise ask for rows far past the end -- an offset large enough that
      # the database refuses the query outright -- and leave the reader on an
      # empty table labelled as though it were full.
      page = to_page_number(query[:page], 1).clamp(1, last_page)

      pagy_instance, records = pagy(:offset, scope, page: page, limit: page_size,
                                                    count: total, request: { params: {} })

      {
        mail_log: records,
        meta: {
          total: pagy_instance.count,
          total_pages: pagy_instance.pages,
          page_size: pagy_instance.limit,
          page: pagy_instance.page
        }
      }
    end

    # Find the logs related to a prospective application
    #
    # @param prospective_application_id [Integer] prospective application identifier
    # @return [ActiveRecord::Relation]
    def find_for_prospective_application(prospective_application_id)
      where(prospective_application_id: prospective_application_id)
        .order(created_at: :asc)
        .includes(:sender)
    end

    # Retrieve the years for a person or the website
    #
    # @param person_id [Integer, nil] person identifier (optional)
    # @return [Array<Integer>] list of years in ascending order
    def retrieve_years(person_id = nil)
      scope = select("DISTINCT YEAR(created_at) as year")

      if person_id.present?
        scope = scope.where("person_id = ? OR sender_id = ?", person_id, person_id)
      end

      scope.order(year: :asc).pluck(:year).sort
    end

    # Retrieve the sending stats for the last 24 hours, the last 7 days, and the
    # whole RETENTION window -- what the nightly cleanup keeps. A calendar year
    # would not fit: from July on it is longer than the window.
    #
    # @param person_id [Integer, nil] person identifier (optional)
    # @return [Hash] { last_24:, week:, retained: }
    def retrieve_stats(person_id)
      {
        last_24: count_for_period(person_id, Current.time - 1.day),
        week: count_for_period(person_id, Current.time - 7.days),
        retained: count_for_period(person_id, Current.time - RETENTION)
      }
    end

    # Mark any records matching the id SES gave the message as having bounced.
    #
    # @param email [String] the email address
    # @param message_id [String] the id SES gave the message (mail.messageId)
    # @return [MailLog, nil] the updated record or nil if not found
    def mark_as_bounced(email, message_id)
      mark_outcome(email, message_id, did_bounce: true)
    end

    # Mark any records matching the id SES gave the message as having a complaint
    # (aka determined to be spam by the recipient's mail server).
    #
    # @param email [String] the email address
    # @param message_id [String] the id SES gave the message (mail.messageId)
    # @return [MailLog, nil] the updated record or nil if not found
    def mark_as_complaint(email, message_id)
      mark_outcome(email, message_id, did_complain: true)
    end

    # Mark any records matching the id SES gave the message as delivered -- the
    # recipient's mail server accepted the message. A message that never gets
    # here was accepted by SES and then went nowhere.
    #
    # @param email [String] the email address
    # @param message_id [String] the id SES gave the message (mail.messageId)
    # @return [MailLog, nil] the updated record or nil if not found
    def mark_as_delivered(email, message_id)
      mark_outcome(email, message_id, delivered_at: Current.time)
    end

    private

    # What the three notification markers share: find the one row this delivery
    # report is about and stamp it. A report can arrive for a message the
    # nightly cleanup has already removed, so a miss is normal and returns nil
    # rather than raising.
    def mark_outcome(email, message_id, attributes)
      mail_log = find_by(message_id: message_id, to_email: email)
      mail_log&.update(attributes)
      mail_log
    end

    # Reads a page or page-size straight from a query string, where the value
    # can be anything at all -- a word, a list, nothing. Only a positive whole
    # number counts; everything else falls back.
    def to_page_number(value, fallback)
      number = Integer(value.to_s, exception: false).to_i

      number.positive? ? number : fallback
    end

    def count_for_period(person_id, since_time)
      scope = where("created_at >= ?", since_time)
      if person_id.present?
        scope = scope.where("person_id = ? OR sender_id = ?", person_id,
person_id)
      end
      scope.count
    end
  end
end
