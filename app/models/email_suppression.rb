# frozen_string_literal: true

# An address the Clubhouse should not email: one that bounced for good, or
# whose owner reported a Clubhouse email as spam. One row per normalized
# address. SES's reports write it (Infrastructure::AwsSnsController), the
# person banner reads it, and an Admin or Tech Ninja clears it
# (Person::EmailSuppressionsController).
#
# Keyed on the address, not the person: a row stays when its person moves to
# another address, because they may come back to it, and nothing on Person
# touches this table. Rows never expire.
#
# SES's own account-level suppression list keeps only complaints, so this is
# the Clubhouse's one guard against mailing a dead address again. The app makes
# no AWS call: clearing a complaint row leaves the address on SES's list, which
# the maintainer clears in the SES console.
class EmailSuppression < ApplicationRecord
  self.table_name = "email_suppression"

  BOUNCE = "bounce"
  COMPLAINT = "complaint"
  REASONS = [BOUNCE, COMPLAINT].freeze

  # The sub-type SES reports when its own suppression list stopped the send.
  ON_ACCOUNT_SUPPRESSION_LIST = "OnAccountSuppressionList"

  # A report SNS delivers again carries the id already stored. Compared with
  # =, so a report with no id is never taken for one already counted.
  SAME_REPORT = "message_id = VALUES(message_id)"

  # MariaDB applies these left to right, each one reading the columns already
  # set, so message_id is compared before it is overwritten. A complaint wins
  # over a bounce: clearing a complaint is the one that needs the SES console,
  # and SES answers a send to an address its list holds for a complaint with an
  # OnAccountSuppressionList bounce.
  ON_REPORT = Arel.sql(<<~SQL.squish)
    report_count = IF(#{SAME_REPORT}, report_count, report_count + 1),
    last_reported_at = IF(#{SAME_REPORT}, last_reported_at, VALUES(last_reported_at)),
    sub_type = IF(#{SAME_REPORT}, sub_type, VALUES(sub_type)),
    updated_at = IF(#{SAME_REPORT}, updated_at, VALUES(updated_at)),
    reason = IF(VALUES(reason) = '#{COMPLAINT}', VALUES(reason), reason),
    message_id = VALUES(message_id)
  SQL

  # One bounce log the bouncing-flag copy counts.
  LoggedBounce = Data.define(:id, :created_at, :sub_type, :message_id)

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true
  validates :reason, inclusion: { in: REASONS }

  # Counts one SES report of address, in one statement, so two reports posted
  # at once cannot both insert. A new address gets a row; an address with one
  # gets this report's date, sub-type and id, and one more to its count.
  #
  # @param address [String] the address the Clubhouse sent to
  # @param reason [String] BOUNCE or COMPLAINT
  # @param sub_type [String, nil] the report's bounceSubType or complaintSubType
  # @param message_id [String, nil] the id SES gave the email (mail.messageId)
  def self.record(address, reason:, sub_type: nil, message_id: nil)
    now = Current.time
    upsert({ email: address, reason:, sub_type:, message_id: message_id.presence, first_reported_at: now,
             last_reported_at: now, report_count: 1, created_at: now, updated_at: now },
           on_duplicate: ON_REPORT)
  end

  # Which of addresses have a row, for either reason, in one query. Answers
  # the caller's own strings: Clubhouse 2 stored addresses as typed, and
  # normalizes never touches a plucked value, so "John@Example.com" matches
  # the row for john@example.com and comes back as "John@Example.com".
  #
  # @param addresses [Array<String>] blank entries are ignored
  # @return [Set<String>]
  def self.suppressed(addresses)
    by_email = Array(addresses).compact_blank.group_by { normalize_value_for(:email, it) }
    return Set.new if by_email.empty?

    where(email: by_email.keys).pluck(:email).flat_map { by_email.fetch(normalize_value_for(:email, it), []) }.to_set
  end

  def self.suppressed?(address) = suppressed([address]).any?

  # A one-time copy of person.is_bouncing, run by the data migration
  # CopyBouncingFlagsToEmailSuppression. Reading the column here is part of
  # replacing it: when is_bouncing is removed, this method is deleted and that
  # migration's up emptied.
  #
  # A flag says only that one Permanent bounce came back since the address last
  # changed, and Clubhouse 2 never acted on it, so one may be years stale. Each
  # flag is copied only when a Permanent email-bouncing log names the person's
  # current address, dated from the first and last of those logs; Clubhouse 2
  # wrote one with each flag and never pruned them. An address that already has
  # a row is left as it is, so running this again adds nothing.
  #
  # @return [Array(Integer, Integer)] how many flagged people were copied, and skipped
  def self.copy_bouncing_flags
    flagged = Person.where(is_bouncing: true).pluck(:id, :email)
    addresses = flagged.to_h { |id, email| [id, normalize_value_for(:email, email.to_s)] }.compact_blank
    bounces = Hash.new { |hash, person_id| hash[person_id] = [] }

    # The event index narrows action_logs to the bounce logs before any data is read.
    ActionLog.select(:id, :target_person_id, :created_at, :data)
             .where(event: "email-bouncing", target_person_id: addresses.keys)
             .find_each(batch_size: 10_000) do |log|
      bounce = logged_bounce(log, addresses[log.target_person_id])
      bounces[log.target_person_id] << bounce if bounce
    end

    taken = where(email: bounces.keys.map { addresses[it] }).pluck(:email).to_set
    rows = bounces.filter_map do |person_id, logs|
      next if taken.include?(addresses[person_id])

      first, last = logs.minmax_by { [it.created_at, it.id] }
      { email: addresses[person_id], reason: BOUNCE, sub_type: last.sub_type, message_id: last.message_id,
        first_reported_at: first.created_at, last_reported_at: last.created_at, report_count: logs.size }
    end
    insert_all(rows) if rows.any?

    [rows.size, flagged.size - rows.size]
  end

  # A Permanent bounce of address from one email-bouncing log, or nil for any
  # other log. ActionLog decodes data itself and raises on a row that does not
  # parse, so this reads the raw column and skips such a row.
  def self.logged_bounce(log, address)
    data = JSON.parse(log.data_before_type_cast.to_s)
    return unless data.is_a?(Hash) && data["bounce_type"] == "Permanent"
    return unless normalize_value_for(:email, data["to_email"].to_s) == address

    LoggedBounce.new(id: log.id, created_at: log.created_at, message_id: data["message_id"].presence,
                     sub_type: data.dig("message", "bounce", "bounceSubType").presence)
  rescue JSON::ParserError, TypeError
    nil
  end
  private_class_method :logged_bounce

  # Deletes the row, and writes an action log naming who cleared it, for whom,
  # and what the row held.
  #
  # @param by [Person] who cleared it
  # @param person [Person] whose address it is
  def clear(by:, person:)
    transaction do
      destroy!
      ActionLog.record(by, "email-suppression-clear", "",
                       slice(:email, :reason, :sub_type, :first_reported_at, :last_reported_at, :report_count,
                             :message_id),
                       person.id)
    end
  end

  def complaint? = reason == COMPLAINT

  # Whether SES's own suppression list holds this address too: it keeps every
  # complaint, and an OnAccountSuppressionList bounce says it held this one.
  # Clearing the row leaves SES refusing mail to it until the address is
  # removed in the SES console.
  def on_ses_list? = complaint? || sub_type == ON_ACCOUNT_SUPPRESSION_LIST
end
