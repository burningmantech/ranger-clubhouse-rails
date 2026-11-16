# frozen_string_literal: true

# What every mailing-list job shares. One lane between them, so the lists take one of the three worker
# threads that also send the mail: a Bulk Team Grant queues a job a person, and an audit makes hundreds of
# calls to Google. Google being unavailable is tried again, with a growing wait.
class MailingListJob < ApplicationJob
  limits_concurrency to: 1, group: "mailing-lists", key: "mailing-lists", duration: 1.hour
  retry_on GoogleGroups::Unavailable, wait: :polynomially_longer, attempts: 5
end
