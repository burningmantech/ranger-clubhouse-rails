# frozen_string_literal: true

class PersonAlert < ApplicationRecord
  self.table_name = "person_alert"

  belongs_to :person
  belongs_to :alert

  class << self
    # Find all alerts with opt-in defaults for a person.
    # Returns Alert records with use_sms and use_email computed columns.
    def find_all_for_person(person_id)
      Alert
        .select(
          "alert.id",
          "alert.title",
          "alert.description",
          "alert.on_playa",
          "COALESCE(person_alert.use_sms, 1) as use_sms",
          "COALESCE(person_alert.use_email, 1) as use_email"
        )
        .joins(
          sanitize_sql_array([
                               "LEFT JOIN person_alert ON person_alert.alert_id = alert.id AND person_alert.person_id = ?",
                               person_id
                             ])
        )
        .where.not(alert: { id: [Alert::RANGER_CONTACT, Alert::MENTOR_CONTACT] })
        .order("alert.on_playa DESC, alert.title ASC")
    end

    # Find or initialize an alert preference for a person
    def find_or_create_for_person(person_id, alert_id)
      find_or_initialize_by(person_id: person_id, alert_id: alert_id)
    end

    # Find an alert preference for a person
    def find_alert_for_person(alert_id, person_id)
      find_by(alert_id: alert_id, person_id: person_id)
    end

    # Check if the person allows email for a given alert
    def allow_email_for_alert?(person_id, alert_id)
      pref = find_by(person_id: person_id, alert_id: alert_id)
      pref.nil? || pref.use_email
    end
  end
end
