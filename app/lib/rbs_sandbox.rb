# frozen_string_literal: true

# Which delivery channels are in sandbox mode: recorded as though they were
# sent, but never actually delivered. Senders are told, because a sandboxed
# broadcast looks exactly like a real one on the results page.
class RbsSandbox
  # Texts, emails and Clubhouse messages: the channels `on` can name.
  CHANNEL_COUNT = 3

  class << self
    # The names of the sandboxed channels, for the notice a sender reads.
    # Email is held back by more than its sandbox -- the training server, and
    # anywhere sending to Rangers is not switched on and no test address is
    # set -- so it is named from the same answer the delivery itself goes by.
    def on(email_mode = Rbs.email_mode)
      {
        "text messages" => Setting.get_value(Setting::BROADCAST_SMS_SANDBOX),
        "emails" => email_mode == :held,
        "Clubhouse messages" => Setting.get_value(Setting::BROADCAST_CLUBHOUSE_SANDBOX)
      }.filter_map { |label, held| label if held }
    end

    # Everything the notice needs, from one reading of the email settings: the
    # channels held back, and the test address while email goes to it.
    def notice
      pattern = Rbs.test_address_pattern
      mode = Rbs.email_mode(pattern)
      [on(mode), (pattern if mode == :test)]
    end

    # Whether anything a sender sends still reaches Rangers: some channel is
    # neither held back nor going to the test address. Email is never both,
    # so each one named accounts for one of the channels `on` can name.
    def anything_live?(sandboxes, test_address)
      sandboxes.size + (test_address.present? ? 1 : 0) < CHANNEL_COUNT
    end

    # The test address broadcast email goes to instead of each Ranger, while it
    # does -- the pattern, with its ? where each Ranger's id goes.
    def email_test_address
      pattern = Rbs.test_address_pattern
      pattern if Rbs.email_mode(pattern) == :test
    end
  end
end
