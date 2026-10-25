# frozen_string_literal: true

class Alert < ApplicationRecord
  self.table_name = "alert"
  self.audit_model = true

  # Alert type constants
  SHIFT_CHANGE = 1
  SHIFT_MUSTER = 2
  EMERGENCY_BROADCAST = 3
  RANGER_SOCIALS = 4
  TICKETING = 5
  ON_SHIFT = 6
  TRAINING = 7
  CLUBHOUSE_NOTIFY_ON_PLAYA = 8
  CLUBHOUSE_NOTIFY_PRE_EVENT = 9
  SHIFT_CHANGE_PRE_EVENT = 10
  SHIFT_MUSTER_PRE_EVENT = 11

  # The following are not part of the RBS and are email only
  RANGER_CONTACT = 12
  MENTOR_CONTACT = 13

  # Associations
  has_many :person_alert, dependent: :delete_all
  has_many :broadcast

  # Validations
  validates :title, presence: true, length: { maximum: 255 }
  validates :description, presence: true

  # Both fields are shown to Rangers exactly as stored, so surrounding
  # whitespace a textarea picked up would show up in the list they read.
  before_validation :trim_text

  # Virtual attributes for computed columns from PersonAlert.find_all_for_person,
  # which returns Alert objects with COALESCE'd use_sms/use_email values.
  # Without these, the integer values (0/1) from COALESCE are not cast to
  # booleans, causing 0 to be truthy in Ruby.
  attribute :use_sms, :boolean
  attribute :use_email, :boolean

  # Computed accessors (virtual attributes for serialization)
  def sms_only
    id == ON_SHIFT
  end

  def email_only
    [RANGER_CONTACT, MENTOR_CONTACT].include?(id)
  end

  def no_opt_out
    id == EMERGENCY_BROADCAST
  end

  class << self
    def find_all
      order(on_playa: :desc, title: :asc)
    end
  end

  private

  def trim_text
    self.title = title&.strip
    self.description = description&.strip
  end
end
