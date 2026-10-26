# frozen_string_literal: true

# Person.find_by_sms_number (every incoming text, STOP included) and
# TwilioMessageLog.people (every page of SMS Management's log) look a person up
# by number, and no key held sms_number, so each one scanned person. Not
# unique: people share numbers, and the inbound webhook takes the lowest id.
class IndexPersonBySmsNumber < ActiveRecord::Migration[8.1]
  def change
    add_index :person, :sms_number
  end
end
