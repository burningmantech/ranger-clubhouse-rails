# frozen_string_literal: true

# Clears the record that email to a person's address bounced for good or was
# reported as spam (EmailSuppression), from the button in the banner on the
# person page and the HQ window. It is for a false positive on an address that
# is right: a wrong address is fixed by changing it, and the new one has no row.
class Person::EmailSuppressionsController < ApplicationController
  include PersonConcern

  # Replaces PersonConcern's VIEW_ROLES (the last call wins). A Tech Ninja with
  # none of them cannot open either page, so never sees the button, but may
  # still clear.
  authorize_role [Role::ADMIN, Role::TECH_NINJA]

  def clear
    suppression = EmailSuppression.find_by(email: @person.email)

    unless suppression
      redirect_back_or_to person_path(@person),
                          info: "No bounce or spam report is recorded for #{@person.callsign}'s email address."
      return
    end

    suppression.clear(by: current_user, person: @person)
    redirect_back_or_to person_path(@person), success: cleared_message(suppression)
  end

  private

  def cleared_message(suppression)
    message = "Cleared the #{suppression.complaint? ? "spam" : "bounce"} report for " \
              "#{@person.callsign}'s email address."
    return message unless suppression.on_ses_list?

    "#{message} SES refuses mail to it until it is also removed in the SES console."
  end
end
