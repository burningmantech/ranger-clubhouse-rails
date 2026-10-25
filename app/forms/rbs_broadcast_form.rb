# frozen_string_literal: true

#
# What a sender chose for one broadcast: who it goes to, over which channels,
# and what it says.
#
# The kind of broadcast decides which fields are asked for and which are
# required, so every rule here is asked of the kind first.
#
# Each message names its own field -- the error summary prints the message on
# its own, so one that does not say what it is about leaves the reader hunting.
#
class RbsBroadcastForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "broadcast"

  SUBJECT_LIMIT = 80
  MESSAGE_LIMIT = 4000

  # How long a message stays relevant, unless the sender says otherwise.
  DEFAULT_EXPIRES_IN = 12.hours

  # The value a date field wants back when the page is redrawn.
  FIELD_FORMAT = "%Y-%m-%d %H:%M"

  attr_reader :type

  # Who it goes to
  attribute :alert_id, :integer
  attribute :position_signed_up, :string, default: Rbs::SIGNED_UP_ANY
  attribute :slot_position_id, :integer
  attribute :slot_id, :integer
  attribute :position_id, :integer
  attribute :position_ids, IdList::Type.new, default: -> { [] }
  attribute :on_site, :boolean, default: true
  attribute :attending, :boolean, default: true
  attribute :training, :string, default: Rbs::TRAINING_ANY

  # Which channels
  attribute :send_sms, :boolean, default: true
  attribute :send_email, :boolean, default: true
  attribute :send_clubhouse, :boolean, default: true

  # What it says
  attribute :sms_message, :string
  attribute :subject, :string
  attribute :message, :string
  attribute :expires_at, :string

  validates :sms_message, length: { maximum: Rbs::SMS_LIMIT,
                                    message: "The text message is longer than one message allows." }
  validates :subject, length: { maximum: SUBJECT_LIMIT,
                                message: "The subject is too long." }
  validates :message, length: { maximum: MESSAGE_LIMIT,
                                message: "The message is too long." }

  validate :channel_chosen
  validate :text_written
  validate :email_written
  validate :audience_chosen
  validate :expiry_makes_sense

  def initialize(type, attributes = {})
    @type = type
    super(attributes)
    self.expires_at = default_expires_at if expires_at.blank? && expiry_asked_for?
    # A page that has been through the form always sends the list, even when it
    # is empty, so an untouched form is the only thing this can start.
    self.statuses = [Person::ACTIVE] if @statuses.nil?
  end

  def statuses = Array(@statuses).compact_blank

  def statuses=(values)
    @statuses = Array(values)
  end

  # -------------------------------------------------------------------------
  # What this kind of broadcast asks for
  # -------------------------------------------------------------------------

  def attrs = Rbs::ATTRIBUTES[type] || {}

  def simple? = attrs[:is_simple].present?

  def sms_only? = attrs[:sms_only].present?

  def has_status? = attrs[:has_status].present?

  def has_position? = attrs[:has_position].present?

  def has_muster_position? = attrs[:has_muster_position].present?

  def has_slot? = attrs[:has_slot].present?

  def has_restrictions? = attrs[:has_restrictions].present?

  def picks_alert? = !simple?

  # A short broadcast always texts, and emails too unless it is text-only.
  def sends_sms? = simple? ? true : send_sms

  def sends_email? = simple? ? !sms_only? : send_email

  def sends_clubhouse? = simple? ? false : send_clubhouse

  def expiry_asked_for? = !simple? || has_muster_position?

  # -------------------------------------------------------------------------
  # What the rest of the system needs from it
  # -------------------------------------------------------------------------

  # Who to reach, in the shape the recipient search expects.
  def criteria
    values = {
      alert_id: Rbs.alert_id_for(type, alert_id),
      send_sms: sends_sms?,
      send_email: sends_email?,
      send_clubhouse: sends_clubhouse?
    }

    values[:statuses] = statuses if has_status? && statuses.any?
    values[:position_ids] = position_ids if has_position?
    values[:position_ids] = [position_id] if has_muster_position?
    values[:position_signed_up] = position_signed_up if has_position?
    values[:slot_id] = slot_id if has_slot?

    if has_restrictions?
      values[:on_site] = on_site
      values[:attending] = attending
      values[:training] = training
    end

    values
  end

  # What it says, in the shape the send expects.
  def message_parts
    {
      sms_message: sends_sms? ? sms_message.to_s : "",
      subject: subject.to_s,
      message: sends_email? || sends_clubhouse? ? message.to_s : "",
      expires_at: expires_at_time
    }
  end

  def expires_at_time
    return nil if expires_at.blank?

    Time.zone.parse(expires_at)
  rescue ArgumentError
    nil
  end

  # Every value the review page carries forward, so the send acts on exactly
  # what was reviewed.
  def carried_values
    {
      alert_id:, position_signed_up:, slot_position_id:, slot_id:, position_id:,
      on_site:, attending:, training:, send_sms:, send_email:, send_clubhouse:,
      sms_message:, subject:, message:, expires_at:,
      statuses:, position_ids:
    }
  end

  private

  def default_expires_at
    (Time.zone.now + DEFAULT_EXPIRES_IN).strftime(FIELD_FORMAT)
  end

  def channel_chosen
    return if simple? || sends_sms? || sends_email? || sends_clubhouse?

    errors.add(:send_sms, "Choose at least one way to send the message.")
  end

  def text_written
    return unless sends_sms?
    return if sms_message.present?

    errors.add(:sms_message, "Enter the text message to send.")
  end

  def email_written
    return unless sends_email? || sends_clubhouse?
    # A short broadcast uses its one message as the subject, and writes no body.
    return if simple?

    errors.add(:subject, "Enter a subject for the email.") if subject.blank?
    errors.add(:message, "Enter the message to send.") if message.blank?
  end

  def audience_chosen
    check_alert
    errors.add(:statuses, "Choose at least one account status.") if has_status? && statuses.empty?
    errors.add(:position_ids, "Choose at least one position.") if has_position? && position_ids.empty?
    errors.add(:position_id, "Choose the position that needs Rangers.") if has_muster_position? && position_id.blank?
    errors.add(:slot_id, "Choose the shift to send to.") if has_slot? && slot_id.blank?

    if has_position? && !Rbs::SIGNED_UP_OPTIONS.include?(position_signed_up)
      errors.add(:position_signed_up, "Choose one of the offered sign-up rules.")
    end

    return unless has_restrictions? && !Rbs::TRAINING_OPTIONS.include?(training)

    errors.add(:training, "Choose one of the offered training rules.")
  end

  # An alert decides who hears about this broadcast and which preference turns
  # it off, so it has to be one this kind of broadcast offers -- not merely one
  # that exists.
  def check_alert
    return unless picks_alert?

    if alert_id.blank?
      errors.add(:alert_id, "Choose an alert type.")
      return
    end

    return if Rbs.alerts_for(type).any? { |alert| alert.id == alert_id }

    errors.add(:alert_id, "Choose one of the offered alert types.")
  end

  def expiry_makes_sense
    return unless expiry_asked_for?

    if expires_at.blank?
      errors.add(:expires_at, "Enter when the message stops being relevant.")
      return
    end

    return if expires_at_time

    errors.add(:expires_at, "Enter a date and time the message stops being relevant.")
  end
end
