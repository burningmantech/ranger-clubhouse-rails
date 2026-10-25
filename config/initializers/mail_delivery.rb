# frozen_string_literal: true

# How ActionMailer mail leaves the building. After initialize, so the
# autoloader is up and aws-sdk-rails has loaded the AWS keys; a test address or
# an SES opt-in set up wrong stops the boot here rather than every email.
Rails.application.config.after_initialize do
  ActionMailer::Base.add_delivery_method :ses_mail, SesMailDelivery

  # Mail runs interceptors in the order they are registered, all of them before
  # the delivery method. The one that drops suppressed addresses goes ahead of
  # the test address: it must see the real recipients before the test address
  # replaces them.
  ActionMailer::Base.register_interceptor SuppressedRecipientsInterceptor
  MailTestAddressInterceptor.validate!
  ActionMailer::Base.register_interceptor MailTestAddressInterceptor

  SesMailDelivery.install!
end
