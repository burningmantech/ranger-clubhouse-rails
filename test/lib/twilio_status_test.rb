# frozen_string_literal: true

require "test_helper"

class TwilioStatusTest < ActiveSupport::TestCase
  include CacheTestHelper
  include FakeTwilioTestHelper

  test "asks Twilio nothing until the account SID and auth token are set" do
    fake = FakeTwilioClient.new

    with_fake_twilio(fake) { assert_nil TwilioStatus.fetch }

    assert_empty fake.asked
  end

  test "reads the account, its balance, each service, the day's texts and the alerts" do
    travel_to Time.utc(2026, 10, 25, 3) do
      configure_twilio(service_ids: "ISservice0001,ISmissing0002")
      filtered = FakeTwilioClient::Alert.new(Time.utc(2026, 10, 25, 2), "30007", "warning",
                                             "ErrorCode=30007&Msg=Message+filtered+by+the+carrier&LogLevel=WARN")
      plain = FakeTwilioClient::Alert.new(Time.utc(2026, 10, 25, 1), "11200", "error", "HTTP retrieval failure")
      texts = [FakeTwilioClient.text, FakeTwilioClient.text, FakeTwilioClient.text(status: "undelivered"),
               FakeTwilioClient.text(status: "received", direction: "inbound"),
               # Listed, since Twilio filters by date, but outside the 24 hours.
               FakeTwilioClient.text(status: "failed", date_sent: 30.hours.ago)]
      fake = FakeTwilioClient.new(texts:, alerts: [filtered, plain])

      status = with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal({ value: { name: "Black Rock Rangers", status: "active", type: "Full", subaccount: false } },
                   status[:account])
      assert_equal({ value: { amount: "412.37", currency: "USD" } }, status[:balance])
      assert_equal({ value: { name: "Ranger Alerts" }, id: "ISservice0001" }, status[:services].first)
      # A service Twilio does not know is an answer of its own; the rest still came.
      assert_equal "The requested resource /Services/ISmissing0002 was not found (Twilio error 20404)",
                   status[:services].last[:error]
      # The Messaging Service TwilioMessagingServiceId names: no Notify
      # service leads to it.
      assert_equal({ value: { incoming_url: FakeTwilioClient::CLUBHOUSE2_INCOMING, fallback_url: nil,
                              defers_to_number: false } }, status[:messaging_service])
      assert_equal({ value: { counts: { "delivered" => 2, "undelivered" => 1, "received" => 1 }, sampled: false } },
                   status[:texts])
      # Twilio is asked for the UTC date the window opens.
      assert_equal "2026-10-24", fake.params[:messages][:date_sent_after]
      assert_equal [{ at: Time.utc(2026, 10, 25, 2), code: 30007, level: "warning", text: "Message filtered by the carrier" },
                    { at: Time.utc(2026, 10, 25, 1), code: 11200, level: "error", text: "HTTP retrieval failure" }],
                   status[:alerts][:value]
      assert_equal({ start_date: Time.utc(2026, 10, 24, 3), limit: TwilioStatus::ALERT_LIMIT }, fake.params[:alerts])
    end
  end

  test "a subaccount's balance is not asked for: its main account keeps it" do
    configure_twilio
    # A subaccount: another account owns it, not its own SID.
    subaccount = FakeTwilioClient::MAIN_ACCOUNT.with(owner_account_sid: "feedface")
    fake = FakeTwilioClient.new(account: subaccount)

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert status[:account][:value][:subaccount]
    assert_equal({ value: { main_account: true } }, status[:balance])
    assert_not_includes fake.asked, :balance
  end

  test "a full page of texts is counted as a sample" do
    configure_twilio
    fake = FakeTwilioClient.new(texts: Array.new(TwilioStatus::MESSAGE_LIMIT) { FakeTwilioClient.text })

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert status[:texts][:value][:sampled]
  end

  test "a full page that reaches back past the 24 hours holds all of them" do
    configure_twilio
    texts = Array.new(TwilioStatus::MESSAGE_LIMIT - 1) { FakeTwilioClient.text } +
            [FakeTwilioClient.text(date_sent: 30.hours.ago)]
    fake = FakeTwilioClient.new(texts:)

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal({ counts: { "delivered" => TwilioStatus::MESSAGE_LIMIT - 1 }, sampled: false }, status[:texts][:value])
  end

  test "an id Twilio cannot be asked about is answered for without asking" do
    configure_twilio(service_ids: "ISservice0001, ISservice0002,,ISservice0003")
    fake = FakeTwilioClient.new

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal ["ISservice0001", " ISservice0002", "", "ISservice0003"], status[:services].pluck(:id)
    assert_equal [TwilioAccount::UNUSABLE_ID] * 2, status[:services][1..2].pluck(:error)
    assert_equal 2, fake.asked.count(:services)
  end

  test "a Messaging Service setting that is empty or holds a space is answered for without asking" do
    fake = FakeTwilioClient.new
    problems = { nil => "TwilioMessagingServiceId is not set",
                 "MG0123 4567" => "TwilioMessagingServiceId holds a space or punctuation, so Twilio cannot be asked about it" }

    problems.each do |id, error|
      configure_twilio(messaging_service_id: id)

      assert_equal({ error: }, with_fake_twilio(fake) { TwilioStatus.fetch }[:messaging_service])
    end
    assert_not_includes fake.asked, :messaging_service
  end

  test "once Twilio cannot be reached, nothing more is asked" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { account: Twilio::REST::TwilioError.new("Failed to open TCP connection") })

    status = with_fake_twilio(fake) { TwilioStatus.fetch }

    assert_equal [:account], fake.asked
    [status[:account], status[:balance], status[:messaging_service], status[:texts], status[:alerts],
     *status[:services]].each do |answer|
      assert_equal "Could not reach Twilio: Failed to open TCP connection", answer[:error]
    end
  end

  test "a slow answer fails alone, and a read missing one is not cached" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { messages: FakeTwilioClient.read_timeout })

    with_cache_store do
      status = with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal "Could not reach Twilio: Net::ReadTimeout with #<TCPSocket:(closed)>", status[:texts][:error]
      # Asked after the slow one, and answered.
      assert_equal [], status[:alerts][:value]

      with_fake_twilio(fake) { TwilioStatus.fetch }

      assert_equal 2, fake.asked.count(:account)
    end
  end

  test "a read that could not reach Twilio is not cached" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { account: Twilio::REST::TwilioError.new("Failed to open TCP connection") })

    with_cache_store do
      with_fake_twilio(fake) { 2.times { TwilioStatus.fetch } }
    end

    assert_equal 2, fake.asked.count(:account)
  end

  test "asks once while the answer is cached, and again on refresh or a changed setting" do
    configure_twilio
    fake = FakeTwilioClient.new

    with_cache_store do
      with_fake_twilio(fake) do
        2.times { TwilioStatus.fetch }
        assert_equal 1, fake.asked.count(:account)

        TwilioStatus.fetch(refresh: true)
        assert_equal 2, fake.asked.count(:account)

        # The cache key follows the settings, so a corrected token is asked
        # about at once rather than after the old answer runs out.
        Setting.find(Setting::TWILIO_AUTH_TOKEN).update!(value: "a-corrected-token")
        TwilioStatus.fetch
        assert_equal 3, fake.asked.count(:account)

        Setting.find(Setting::TWILIO_MESSAGING_SERVICE_ID).update!(value: "MGfedcba9876543210fedcba9876543210")
        TwilioStatus.fetch
        assert_equal 4, fake.asked.count(:account)
      end
    end
  end

  # ------------------------------------------------- one cold read at a time

  # A client whose account read says it has begun, then waits to be let go:
  # the request holding the lock, part-way through its read.
  def stuck_client(started, release)
    Class.new(FakeTwilioClient) do
      define_method(:fetch) do
        started << true
        release.pop
        super()
      end
    end.new
  end

  # Hands out the clients given, one a build, then puts the real builder back.
  def with_clients(*clients)
    original = TwilioAccount.method(:build_client)
    TwilioAccount.define_singleton_method(:build_client) { |*| clients.shift }
    yield
  ensure
    TwilioAccount.define_singleton_method(:build_client, original)
  end

  def with_wait_limit(seconds)
    original = TwilioStatus.method(:wait_limit)
    TwilioStatus.define_singleton_method(:wait_limit) { seconds }
    yield
  ensure
    TwilioStatus.define_singleton_method(:wait_limit, original)
  end

  # A cold read held part-way by its reader for the block, which is let go
  # however the block ends, so no test is left waiting on it.
  def while_another_reads(started, release)
    reader = Thread.new { TwilioStatus.fetch }
    started.pop(timeout: 5) or flunk "the reader never began its read"
    yield reader
  ensure
    release << true
    reader&.join(5)
  end

  def seconds_taken
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  end

  test "two cold reads at once ask Twilio once: the second takes the first's answer" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    first = stuck_client(started, release)
    second = FakeTwilioClient.new

    with_cache_store do
      with_clients(first, second) do
        while_another_reads(started, release) do |reader|
          waiter = Thread.new { TwilioStatus.fetch }
          Thread.pass until waiter.status == "sleep" || !waiter.alive?
          release << true

          assert_equal reader.value, waiter.value
        end
      end
    end

    assert_equal 1, first.asked.count(:account)
    assert_empty second.asked, "the second request asked Twilio nothing"
  end

  test "a request that waits past the limit asks Twilio itself, and never hangs" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    second = FakeTwilioClient.new
    taken = nil

    with_cache_store do
      with_clients(stuck_client(started, release), second) do
        with_wait_limit(0.3) do
          while_another_reads(started, release) do
            taken = seconds_taken { assert TwilioStatus.fetch }
          end
        end
      end
    end

    assert_operator taken, :>=, 0.3
    assert_operator taken, :<, 3
    assert_equal 1, second.asked.count(:account)
  end

  test "Refresh asks Twilio at once, though another request is reading" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    second = FakeTwilioClient.new
    taken = nil

    with_cache_store do
      with_clients(stuck_client(started, release), second) do
        while_another_reads(started, release) do
          taken = seconds_taken { TwilioStatus.fetch(refresh: true) }
        end
      end
    end

    assert_operator taken, :<, TwilioStatus::WAIT_STEP
    assert_equal 1, second.asked.count(:account)
  end

  test "a request waits on another's read as long as the lock lasts, not one call's timeout" do
    # A read is several calls to Twilio, one after another.
    assert_equal TwilioStatus::LOCK_FOR.to_i, TwilioStatus.wait_limit
  end

  # Solid Cache with its rows in a Hash: production's store, its local cache
  # included, without the database.
  class RowlessSolidCache < SolidCache::Store
    def initialize(...)
      super
      @rows = {}
      @rows_lock = Mutex.new
    end

    private

    def entry_read(key) = @rows_lock.synchronize { @rows[key] }
    def entry_delete(key) = @rows_lock.synchronize { !@rows.delete(key).nil? }

    def entry_write(key, payload)
      @rows_lock.synchronize { @rows[key] = payload }
      true
    end

    def entry_lock_and_write(key)
      @rows_lock.synchronize do
        value = yield @rows[key]
        @rows[key] = value if value
        value
      end
    end
  end

  test "in production's local cache, a waiting request still takes the other's answer" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    first = stuck_client(started, release)
    second = FakeTwilioClient.new

    with_cache_store(RowlessSolidCache.new) do |store|
      with_clients(first, second) do
        # Each runs as a request does, in a local cache of its own, which
        # keeps the waiter's first miss for the rest of it.
        as_request = -> { store.with_local_cache { TwilioStatus.fetch } }
        reader = Thread.new(&as_request)
        started.pop(timeout: 5)
        waiter = Thread.new(&as_request)
        Thread.pass until waiter.status == "sleep" || !waiter.alive?
        release << true

        assert_equal reader.value, waiter.value
      ensure
        release << true
        reader&.join(5)
      end
    end

    assert_empty second.asked, "the second request asked Twilio nothing"
  end

  # A memory store that runs a hook when a read misses the answer (never the
  # lock), so a test can let the reader finish at the worst moment.
  class MissHookStore < ActiveSupport::Cache::MemoryStore
    attr_accessor :on_miss

    def read(name, options = nil)
      super.tap { |value| on_miss&.call if value.nil? && !name.include?("reading") }
    end
  end

  test "a request that takes the lock as another lets go still takes that answer" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    second = FakeTwilioClient.new

    with_cache_store(MissHookStore.new) do |store|
      with_clients(stuck_client(started, release), second) do
        while_another_reads(started, release) do |reader|
          # This request misses the answer; the reader caches it and lets go
          # before this request tries the lock, which it then takes.
          store.on_miss = lambda do
            store.on_miss = nil
            release << true
            reader.join
          end
          answer = TwilioStatus.fetch

          assert_equal reader.value, answer
        end
      end
    end

    assert_empty second.asked
  end

  test "a request waiting as the other lets go still takes that answer" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    second = FakeTwilioClient.new

    with_cache_store(MissHookStore.new) do |store|
      with_clients(stuck_client(started, release), second) do
        while_another_reads(started, release) do |reader|
          # The second miss is the wait's: the reader caches its answer and
          # lets go just after it, before the wait looks at the lock again.
          misses = 0
          store.on_miss = lambda do
            next unless (misses += 1) == 2

            release << true
            reader.join
          end
          answer = TwilioStatus.fetch

          assert_equal reader.value, answer
        end
      end
    end

    assert_empty second.asked
  end

  test "a reader whose lock ran out leaves the next request's lock alone" do
    configure_twilio
    started = Queue.new
    release = Queue.new

    with_cache_store do |store|
      with_clients(stuck_client(started, release)) do
        while_another_reads(started, release) do |reader|
          # As if the reader's lock had run out and another request taken one.
          lock = store.instance_variable_get(:@data).keys.grep(/reading\z/).sole
          store.write(lock, "another request's")
          release << true
          reader.join

          assert_equal "another request's", store.read(lock)
        end
      end
    end
  end

  # A memory store whose add-only write answers true though the key is there,
  # as Solid Cache does when it swallows a deadlock between two such writes.
  class SwallowingStore < ActiveSupport::Cache::MemoryStore
    def write(name, value, options = nil)
      options&.dig(:unless_exist) && exist?(name) ? true : super
    end
  end

  test "when the store lets two requests take the lock, only the one whose token stayed reads Twilio" do
    configure_twilio
    started = Queue.new
    release = Queue.new
    first = stuck_client(started, release)
    second = FakeTwilioClient.new

    with_cache_store(SwallowingStore.new) do
      with_clients(first, second) do
        while_another_reads(started, release) do |reader|
          waiter = Thread.new { TwilioStatus.fetch }
          Thread.pass until waiter.status == "sleep" || !waiter.alive?
          release << true

          assert_equal reader.value, waiter.value
        end
      end
    end

    assert_empty second.asked
  end
end
