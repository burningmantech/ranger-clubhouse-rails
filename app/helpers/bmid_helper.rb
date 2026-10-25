# frozen_string_literal: true

# Select options and readiness formatting for the person BMID admin page.
module BmidHelper
  # The statuses an admin may set, matching the BmidController update whitelist.
  BMID_STATUS_OPTIONS = [
    ["Prep", Bmid::IN_PREP],
    ["Ready to Print", Bmid::READY_TO_PRINT],
    ["Ready to Reprint — Changed", Bmid::READY_TO_REPRINT_CHANGE],
    ["Ready to Reprint — Lost", Bmid::READY_TO_REPRINT_LOST],
    ["Issues", Bmid::ISSUES],
    ["Do Not Print", Bmid::DO_NOT_PRINT],
    ["Submitted", Bmid::SUBMITTED]
  ].freeze

  # Why the SAP date field is locked, or what it does when it is not. A past
  # year comes first: the pass on that badge is the one the person holds for the
  # NEXT event, so saying "no SAP on file" there would be wrong as well as
  # unhelpful.
  def bmid_sap_help_text(bmid)
    if !bmid.current_event_year?
      "Locked: this badge is from a previous year. The pass shown is the person's current one."
    elsif bmid.sap.nil?
      "Locked: no changeable SAP on file."
    elsif bmid.sap_submitted?
      "Locked: the SAP has gone off to be printed."
    else
      "Sets the access date on the person's SAP & Staff Credential."
    end
  end

  # The stat box's value for the printed SAP date. ui_stat_box styles the
  # variant; this only decides the words.
  def bmid_sap_badge_value(bmid)
    if bmid.sap.nil?
      "None"
    elsif bmid.access_any_time
      "Any"
    elsif bmid.access_date
      wday_month_day_format(bmid.access_date.to_date)
    else
      "Unspecified"
    end
  end
end
