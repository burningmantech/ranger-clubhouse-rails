# frozen_string_literal: true

require "net/http"

# How much of its CPU and memory the Fargate task serving this request is using,
# read from the task metadata endpoint ECS gives every task (version 4). It
# covers this one task only, needs no AWS credentials or permissions, and has
# no history: the numbers are as of the request.
module FargateUsage
  # ECS sets this in every container of a Fargate task. Unset means not on Fargate.
  ENDPOINT_ENV = "ECS_CONTAINER_METADATA_URI_V4"
  # Memory at or past this percent marks the task Near Limit. CPU never does: its
  # reading covers about a second, and one request fills a quarter of a vCPU.
  NEAR_LIMIT = 80

  # The endpoint did not answer, or answered with something other than a task and its stats.
  class Unavailable < StandardError; end

  TRANSPORT_ERRORS = [Timeout::Error, SystemCallError, SocketError, IOError, Net::ProtocolError, JSON::ParserError].freeze

  # cpu_limit is in vCPUs, the memory figures in MiB; both limits are the task definition's.
  # cpu_percent is nil when no container has two samples to measure between.
  Usage = Data.define(:service, :cluster, :task_id, :zone, :cpu_limit, :cpu_percent, :memory_limit, :memory_used) do
    def memory_percent = memory_used.fdiv(memory_limit) * 100
    def near_limit? = memory_percent >= NEAR_LIMIT
  end

  module_function

  # The usage, or nil when this server is not a Fargate task. Raises Unavailable.
  def fetch
    task, stats = answers
    read(task, stats) if task
  end

  # The endpoint's /task and /task/stats answers, over one connection. nil off Fargate.
  def answers
    base = ENV[ENDPOINT_ENV] or return
    uri = URI(base)
    Net::HTTP.start(uri.host, uri.port, open_timeout: 2, read_timeout: 2) do |http|
      %w[task task/stats].map { |path| JSON.parse(http.get("#{uri.path}/#{path}").tap(&:value).body) }
    end
  rescue *TRANSPORT_ERRORS => e
    raise Unavailable, e.message
  end

  # A container that is not running has a null entry in stats and counts for nothing.
  def read(task, stats)
    limits = task["Limits"] if task.is_a?(Hash)
    cpu, memory = limits.values_at("CPU", "Memory") if limits.is_a?(Hash)
    unless stats.is_a?(Hash) && [cpu, memory].all? { it.is_a?(Numeric) && it.positive? }
      raise Unavailable, "its answer was not a task with CPU and memory limits."
    end

    containers = stats.values.grep(Hash)
    cpus = containers.filter_map { cpus_used(it) }
    Usage.new(service: task["ServiceName"], cluster: task["Cluster"].to_s.split("/").last,
              task_id: task["TaskARN"].to_s.split("/").last, zone: task["AvailabilityZone"],
              cpu_limit: cpu, cpu_percent: (cpus.sum.fdiv(cpu) * 100 if cpus.any?),
              memory_limit: memory, memory_used: containers.sum { memory_used(it) } / 1.megabyte)
  end

  # vCPUs in use between the container's last two samples: its share of the host's
  # CPU time, times the host's CPUs (the sum Docker's own `stats` does). nil when
  # there is no earlier sample or no CPU count to measure with.
  def cpus_used(stat)
    now, before = stat.values_at("cpu_stats", "precpu_stats").map { it.is_a?(Hash) ? it : {} }
    host_before = before["system_cpu_usage"].to_i
    host = now["system_cpu_usage"].to_i - host_before
    cpus = now["online_cpus"] || Array(now.dig("cpu_usage", "percpu_usage")).size
    return unless host_before.positive? && host.positive? && cpus.to_i.positive?

    (now.dig("cpu_usage", "total_usage").to_i - before.dig("cpu_usage", "total_usage").to_i).fdiv(host) * cpus
  end

  # Bytes held, less the page cache the kernel gives back under pressure.
  def memory_used(stat)
    memory = stat["memory_stats"].is_a?(Hash) ? stat["memory_stats"] : {}
    stats = memory["stats"].is_a?(Hash) ? memory["stats"] : {}
    memory["usage"].to_i - stats.values_at("total_inactive_file", "inactive_file").compact.first.to_i
  end
end
