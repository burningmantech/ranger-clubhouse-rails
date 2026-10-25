# frozen_string_literal: true

# Status change warning messages.
# ACTIVE_WARNINGS: warnings when changing FROM active status, keyed by new status.
# OTHER_WARNINGS: warnings when changing from any other status, keyed by new status.
#
# Messages containing %{old_status} or %{status} are format strings intended
# for use with format() or the % operator.

module StatusChangeWarnings
  ACTIVE_WARNINGS = {
    Person::ALPHA => {
      title: "Confirm Alpha Conversion",
      message: "<p>You are about to convert an %{old_status} account to an Alpha account. This is highly unusual. " \
        "Normally, only Prospective accounts are converted to Alpha status.</p>Convert this account to Alpha?"
    },
    Person::AUDITOR => {
      title: "Confirm Auditor Conversion",
      message: "<p>You are about to convert a %{old_status} account to Auditor. This is highly unusual.</p>" \
        "Convert this account to Auditor?"
    },
    Person::BONKED => {
      title: "Confirm Bonked Conversion",
      message: '<p><b class="text-error">You are about to bonk an account with the status %{old_status}.</b> ' \
        "This is highly unusual. Normally only Prospective, Alpha, and Past Prospective accounts are eligible.</p>" \
        "Bonk this account?"
    },
    Person::DECEASED => {
      title: "Confirm Destructive Status Update",
      message: '<p>You are about to update the account status to <b class="text-error">%{status}</b>. ' \
        "All team memberships will be removed, all positions revoked, and all permissions rescinded. " \
        "The account will be locked and no further logins allowed.</p>Change the status to %{status}?"
    },
    Person::DISMISSED => {
      title: "Confirm Destructive Status Update",
      message: '<p>You are about to update the account status to <b class="text-error">%{status}</b>. ' \
        "All team memberships will be removed, all positions revoked, and all permissions rescinded. " \
        "The account will be locked and no further logins allowed.</p>Change the status to %{status}?"
    },
    Person::INACTIVE => {
      title: "Confirm Inactive Status",
      message: "<p>Conversion to inactive status is normally handled through the Status Change Recommendations interface " \
        "run by Council post-event.</p>Change the status to inactive?"
    },
    Person::INACTIVE_EXTENSION => {
      title: "Confirm Inactive Extension Status",
      message: "<p>All inactive extension updates MUST be approved by Council first.</p>Change the status to inactive extension?"
    },
    Person::ECHELON => {
      title: "Confirm Status Update",
      message: "<p>You are about to convert an account from %{old_status} status to Echelon. " \
        "Normally only auditor accounts are eligible.</p>Convert this account to Echelon?"
    },
    Person::RESIGNED => {
      title: "Confirm Resigned Status",
      message: "<p>Usually only Council and the Personnel Managers handle a retirement request.</p>" \
        "Change the status to resigned?"
    },
    Person::RETIRED => {
      title: "Confirm Retired Status",
      message: "<p>Conversion to retired status is normally done through the Status Change Recommendations interface " \
        "run by Council post-event.</p>Change the status to retired?"
    },
    Person::PROSPECTIVE => {
      title: "Confirm Prospective Status",
      message: "<p>Updating an account from %{old_status} status to prospective is highly unusual. " \
        "Normally only Auditor, Echelon, and Past Prospective accounts are eligible.</p>" \
        "Change the status to prospective?"
    },
    Person::PAST_PROSPECTIVE => {
      title: "Confirm Past Prospective Status",
      message: "<p>Updating an account from %{old_status} status to past prospective is a highly unusual step. " \
        "Normally, only Prospective or Alpha accounts are eligible to be converted.</p>" \
        "Change the status to past prospective?"
    },
    Person::SUSPENDED => {
      title: "Confirm Suspended Status",
      message: "<p>While suspended, the account will be locked and no logins allowed. Team membership, position grants, " \
        "and Clubhouse permissions will not be lost. Only Council and the Personnel Managers are authorized to " \
        "suspend accounts.</p>Suspend this account?"
    },
    Person::UBERBONKED => {
      title: "Confirm Uberbonked Conversion",
      message: "<p>You are about to UBERBONK an account. The account will be locked and no further logins allowed.</p>" \
        "Uberbonk this account?"
    }
  }.freeze

  OTHER_WARNINGS = {
    Person::ALPHA => {
      title: "Confirm Alpha Conversion",
      message: "<p>You are about to convert an %{old_status} account to an Alpha account. This is highly unusual. " \
        "Normally, only Prospective accounts are converted to Alpha status.</p>Convert this account to Alpha?"
    },
    Person::AUDITOR => {
      title: "Confirm Auditor Conversion",
      message: "<p>You are about to convert a %{old_status} account to Auditor. This is highly unusual.</p>" \
        "Convert this account to Auditor?"
    },
    Person::BONKED => {
      title: "Confirm Bonked Conversion",
      message: '<p><b class="text-error">You are about to bonk an account with the status %{old_status}.</b> ' \
        "This is highly unusual. Normally only Prospective, Alpha, and Past Prospective accounts are eligible.</p>" \
        "Bonk this account?"
    },
    Person::DECEASED => {
      title: "Confirm Destructive Status Update",
      message: '<p>You are about to update the account status to <b class="text-error">%{status}</b>. ' \
        "All team memberships will be removed, all positions revoked, and all permissions rescinded. " \
        "The account will be locked and no further logins allowed.</p>Change the status to %{status}?"
    },
    Person::DISMISSED => {
      title: "Confirm Destructive Status Update",
      message: '<p>You are about to update the account status to <b class="text-error">%{status}</b>. ' \
        "All team memberships will be removed, all positions revoked, and all permissions rescinded. " \
        "The account will be locked and no further logins allowed.</p>Change the status to %{status}?"
    },
    Person::INACTIVE => {
      title: "Confirm Inactive Status",
      message: "<p>Conversion to inactive status is normally handled through the Status Change Recommendations interface " \
        "run by Council post-event.</p>Change the status to inactive?"
    },
    Person::INACTIVE_EXTENSION => {
      title: "Confirm Inactive Extension Status",
      message: "<p>All inactive extension updates MUST be approved by Council first.</p>Change the status to inactive extension?"
    },
    Person::ECHELON => {
      title: "Confirm Status Update",
      message: "<p>You are about to convert an account from %{old_status} status to Echelon. " \
        "Normally only auditor accounts are eligible.</p>Convert this account to Echelon?"
    },
    Person::RESIGNED => {
      title: "Confirm Resigned Status",
      message: "<p>Usually only Council and the Personnel Managers handle a retirement request.</p>" \
        "Change the status to resigned?"
    },
    Person::RETIRED => {
      title: "Confirm Retired Status",
      message: "<p>Conversion to retired status is normally done through the Status Change Recommendations interface " \
        "run by Council post-event.</p>Change the status to retired?"
    },
    Person::PROSPECTIVE => {
      title: "Confirm Prospective Status",
      message: "<p>Updating an account from %{old_status} status to prospective is highly unusual. " \
        "Normally only Auditor, Echelon, and Past Prospective accounts are eligible.</p>" \
        "Change the status to prospective?"
    },
    Person::PAST_PROSPECTIVE => {
      title: "Confirm Past Prospective Status",
      message: "<p>Updating an account from %{old_status} status to past prospective is a highly unusual step. " \
        "Normally, only Prospective or Alpha accounts are eligible to be converted.</p>" \
        "Change the status to past prospective?"
    },
    Person::SUSPENDED => {
      title: "Confirm Suspended Status",
      message: "<p>While suspended, the account will be locked and no logins allowed. Team membership, position grants, " \
        "and Clubhouse permissions will not be lost. Only Council and the Personnel Managers are authorized to " \
        "suspend accounts.</p>Suspend this account?"
    },
    Person::UBERBONKED => {
      title: "Confirm Uberbonked Conversion",
      message: "<p>You are about to UBERBONK an account. The account will be locked and no further logins allowed.</p>" \
        "Uberbonk this account?"
    }
  }.freeze

  module_function

  # The message is written as markup on purpose -- it has paragraphs, and the
  # destructive ones put the new status in bold. Filling it in with `%` rather
  # than format() is what keeps that safe: the wording here is trusted and
  # stays markup, while the two statuses dropped into it are escaped on the way
  # in. Written with format() the statuses would arrive as markup too, and the
  # dialog shows what it is given.
  def warning_for(old_status:, new_status:)
    warning = warning_set_for(old_status)[new_status]
    return nil unless warning

    {
      title: format(warning[:title], old_status:, status: new_status),
      message: warning[:message].html_safe % { old_status:, status: new_status }
    }
  end

  def warnings_for(old_status:)
    warning_set_for(old_status).each_with_object({}) do |(new_status, _warning), warnings|
      warnings[new_status] = warning_for(old_status:, new_status:)
    end
  end

  def warning_set_for(old_status)
    (old_status == Person::ACTIVE) ? ACTIVE_WARNINGS : OTHER_WARNINGS
  end
end
