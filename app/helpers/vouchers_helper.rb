# frozen_string_literal: true

module VouchersHelper
  # The page's first line for each Voucher state: callout variant, icon, title
  # and sentence. Colour never carries it alone; the title says the answer.
  VOUCHER_VERDICTS = {
    ranger: [:success, "circle-check", "Black Rock Ranger",
             "This person is a Black Rock Ranger."],
    applicant: [:info, "user-clock", "Applicant, Not Yet a Ranger",
                "This person has applied to become a Black Rock Ranger. They are not a Ranger yet."],
    echelon: [:warning, "circle-xmark", "Not a Ranger",
              "This person is not a Black Rock Ranger."],
    not_ranger: [:warning, "circle-xmark", "Not a Ranger",
                 "This person is not a Black Rock Ranger."],
    unavailable: [:secondary, "circle-question", "Information Not Available",
                  "Information about this person is not available at this time."]
  }.freeze

  def voucher_verdict(voucher) = VOUCHER_VERDICTS.fetch(voucher.state)
end
