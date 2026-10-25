# frozen_string_literal: true

# The button in the email banner on the person page and in the HQ window
# (person/_banners) that clears an address's EmailSuppression row.
module Person::EmailSuppressionHelper
  # A POST behind a confirmation that says what clearing does, and, when SES's
  # own suppression list holds the address too, that clearing here leaves it
  # there. SES answers a send to such an address with an OnAccountSuppressionList
  # bounce, so even a cleared spam report comes back as a bounce.
  def email_suppression_clear_button(person, suppression)
    label = suppression.complaint? ? "Clear Spam Report" : "Clear Bounce Report"
    paragraphs = [tag.p("Clearing removes this report, and the warning goes away. " \
                        "Clear it only when you know the address is correct.")]
    if suppression.on_ses_list?
      paragraphs << tag.p("Amazon SES also holds this address on its suppression list, and only someone with " \
                          "access to the SES console can remove it there. Until then, SES refuses mail to it, " \
                          "and the next broadcast email records it as bounced.")
    end

    button_link label, :secondary, person_email_suppression_clear_path(person), method: :post,
                data: { turbo_confirm: confirm_modal_dialog(title: label, message: safe_join(paragraphs),
                                                            confirm_label: label, variant: :error) }
  end
end
