# frozen_string_literal: true

require "test_helper"
require "socket"

class FargateUsageTest < ActiveSupport::TestCase
  TASK = { "Cluster" => "arn:aws:ecs:us-west-2:123456789012:cluster/rangers",
           "TaskARN" => "arn:aws:ecs:us-west-2:123456789012:task/rangers/abc123",
           "AvailabilityZone" => "us-west-2a", "Limits" => { "CPU" => 0.25, "Memory" => 2048 } }.freeze
  # A tenth of one of the host's two CPUs' time between the samples: 0.2 vCPU.
  WEB = { "cpu_stats" => { "cpu_usage" => { "total_usage" => 3_000 }, "system_cpu_usage" => 30_000, "online_cpus" => 2 },
          "precpu_stats" => { "cpu_usage" => { "total_usage" => 2_000 }, "system_cpu_usage" => 20_000, "online_cpus" => 2 },
          "memory_stats" => { "usage" => 1100.megabytes, "stats" => { "total_inactive_file" => 76.megabytes } } }.freeze

  test "adds up the running containers against the task's limits" do
    # The migrate container has exited.
    usage = FargateUsage.read(TASK, "web" => WEB, "migrate" => nil)

    assert_equal "rangers", usage.cluster
    assert_equal "abc123", usage.task_id
    assert_nil usage.service
    assert_in_delta 80, usage.cpu_percent
    assert_equal 1024, usage.memory_used
    assert_in_delta 50, usage.memory_percent
    assert_not_predicate usage, :near_limit?, "CPU alone never marks the task"
  end

  test "memory past the mark is near the limit" do
    usage = FargateUsage.read(TASK, "web" => { "memory_stats" => { "usage" => 1700.megabytes } })

    assert_predicate usage, :near_limit?
  end

  test "CPU is unknown without an earlier sample or a CPU count" do
    first_sample = WEB.merge("precpu_stats" => { "cpu_usage" => { "total_usage" => 0 } })
    no_count = WEB.merge("cpu_stats" => WEB["cpu_stats"].except("online_cpus"))

    assert_nil FargateUsage.read(TASK, "web" => first_sample).cpu_percent
    assert_nil FargateUsage.read(TASK, "web" => no_count).cpu_percent
    assert_nil FargateUsage.read(TASK, "web" => { "cpu_stats" => {}, "precpu_stats" => {}, "memory_stats" => {} }).cpu_percent
  end

  test "the CPU count falls back to the per-CPU readings" do
    stats = WEB.merge("cpu_stats" => { "cpu_usage" => { "total_usage" => 3_000, "percpu_usage" => [1, 2] },
                                       "system_cpu_usage" => 30_000 })

    assert_in_delta 80, FargateUsage.read(TASK, "web" => stats).cpu_percent
  end

  test "refuses an answer that is not a task with limits" do
    [[TASK.merge("Limits" => { "CPU" => 0, "Memory" => 2048 }), {}], [TASK.except("Limits"), {}],
     ["nope", {}], [TASK, "nope"]].each do |task, stats|
      assert_raises(FargateUsage::Unavailable) { FargateUsage.read(task, stats) }
    end
  end

  test "answers nil off Fargate without asking anything" do
    with_endpoint(nil) { assert_nil FargateUsage.fetch }
  end

  test "reads the task and its stats from the endpoint" do
    paths = serve([200, TASK.to_json], [200, { "web" => WEB }.to_json]) do
      assert_in_delta 80, FargateUsage.fetch.cpu_percent
    end

    assert_equal %w[/v4/abc/task /v4/abc/task/stats], paths
  end

  test "a refusal, a broken answer and a closed door are all Unavailable" do
    serve([500, "{}"]) { assert_raises(FargateUsage::Unavailable) { FargateUsage.fetch } }
    serve([200, "<html>"]) { assert_raises(FargateUsage::Unavailable) { FargateUsage.fetch } }
    serve { assert_raises(FargateUsage::Unavailable) { FargateUsage.fetch } }
  end

  private

  def with_endpoint(url)
    original = ENV[FargateUsage::ENDPOINT_ENV]
    ENV[FargateUsage::ENDPOINT_ENV] = url
    yield
  ensure
    ENV[FargateUsage::ENDPOINT_ENV] = original
  end

  # A one-connection endpoint answering each request in turn with [status, body], then
  # hanging up. Returns the paths asked for.
  def serve(*replies)
    server = TCPServer.new("127.0.0.1", 0)
    paths = []
    thread = Thread.new do
      socket = server.accept
      replies.each do |status, body|
        paths << socket.gets.to_s.split[1]
        nil until socket.gets.to_s.strip.empty?
        socket.write "HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
      end
      socket.close
    end
    with_endpoint("http://127.0.0.1:#{server.addr[1]}/v4/abc") { yield }
    paths
  ensure
    thread&.kill
    server&.close
  end
end
