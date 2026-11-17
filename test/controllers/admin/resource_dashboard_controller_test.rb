# frozen_string_literal: true

require "test_helper"

class Admin::ResourceDashboardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Current.reset

    @tech_ninja = person(:echelon_ranger)
    @admin = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown { Current.reset }

  test "denies access without the tech ninja role" do
    sign_in_as(@admin)

    get admin_resource_dashboard_path

    assert_redirected_to me_root_path
  end

  test "says so when the server is not on Fargate" do
    sign_in_as(@tech_ninja)

    get admin_resource_dashboard_path

    assert_response :success
    assert_select "h1", text: /Resource Dashboard/
    assert_includes response.body, "not running on Fargate"
  end

  test "shows the task's usage and marks it near its limit" do
    sign_in_as(@tech_ninja)

    task = { "Cluster" => "arn:aws:ecs:us-west-2:123456789012:cluster/rangers", "ServiceName" => "clubhouse-production",
             "TaskARN" => "arn:aws:ecs:us-west-2:123456789012:task/rangers/abc123", "AvailabilityZone" => "us-west-2a",
             "Limits" => { "CPU" => 0.25, "Memory" => 2048 } }
    stats = { "web" => {
      "cpu_stats" => { "cpu_usage" => { "total_usage" => 3_000 }, "system_cpu_usage" => 30_000, "online_cpus" => 2 },
      "precpu_stats" => { "cpu_usage" => { "total_usage" => 2_000 }, "system_cpu_usage" => 20_000, "online_cpus" => 2 },
      "memory_stats" => { "usage" => 1792.megabytes }
    } }
    with_metadata(-> { [task, stats] }) { get admin_resource_dashboard_path }

    assert_response :success
    assert_includes response.body, "clubhouse-production"
    assert_includes response.body, "Near Limit"
    assert_includes response.body, "task abc123"
    assert_match(/80% · of 0.25 vCPU, last second/, response.body)
    assert_match(/88% · 1,792 of 2,048 MB/, response.body)
  end

  test "shows a notice in place of a crash when the endpoint does not answer" do
    sign_in_as(@tech_ninja)

    with_metadata(-> { raise FargateUsage::Unavailable, "Connection refused" }) { get admin_resource_dashboard_path }

    assert_response :success
    assert_includes response.body, "Usage Is Not Available"
  end

  private

  # The task metadata endpoint answers with the [task, stats] the callable returns.
  def with_metadata(answer)
    original = FargateUsage.method(:answers)
    FargateUsage.define_singleton_method(:answers, &answer)
    yield
  ensure
    FargateUsage.define_singleton_method(:answers, original)
  end
end
