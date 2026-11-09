# frozen_string_literal: true

require "test_helper"
require "open3"

# Both deploy jobs build the migrate container with one step (.github/workflows/). These tests run
# that step's script the way Actions does, on a made-up task definition; nothing reaches AWS.
class DeployWorkflowsTest < ActiveSupport::TestCase
  WORKFLOWS = { "cicd.yml" => "deploy-staging", "deploy.yml" => "push-to-production" }.freeze
  STEP_NAME = "Add the migrate container"
  WEB_IMAGE = "repo@sha256:#{"a" * 64}"

  test "both deploy jobs carry the same step, between the render and the deploy" do
    migrate_steps = WORKFLOWS.map do |file, job|
      steps = YAML.load_file(Rails.root.join(".github/workflows", file)).dig("jobs", job, "steps")
      at = steps.index { |step| step["name"] == STEP_NAME }

      assert at, file
      assert_equal "new-task-definition", steps[at - 1]["id"], file
      assert_equal "${{ steps.with-migrate.outputs.task-definition }}", steps[at + 1].dig("with", "task-definition"), file
      steps[at]
    end

    assert_equal migrate_steps.first, migrate_steps.last
  end

  test "adds a migrate container that the web container waits on" do
    definition = task_definition
    result = run_step(definition)
    web, migrate = containers(result).values_at("web", "migrate")

    assert_equal [{ "containerName" => "migrate", "condition" => "SUCCESS" }], web["dependsOn"]
    assert_equal false, migrate["essential"]
    assert_equal %w[bin/rails deploy:migrate], migrate["command"]
    assert_equal WEB_IMAGE, migrate["image"]
    assert_equal web["environment"], migrate["environment"]
    assert_equal web["logConfiguration"], migrate["logConfiguration"]
    assert_nil migrate["portMappings"]
    assert_nil migrate["dependsOn"]
    assert_equal definition.except("containerDefinitions"), result.except("containerDefinitions")
  end

  test "a later roll rebuilds the migrate container from the new web container" do
    rolled = run_step(task_definition)
    new_image = "repo@sha256:#{"b" * 64}"
    rolled["containerDefinitions"].find { _1["name"] == "web" }["image"] = new_image
    result = run_step(rolled)

    assert_equal new_image, containers(result)["migrate"]["image"]
    assert_equal 2, result["containerDefinitions"].size
    assert_equal result, run_step(result)
  end

  test "keeps the web container's other dependencies, and the migrate container waits for them too" do
    definition = task_definition
    router = { "containerName" => "log-router", "condition" => "START" }
    definition["containerDefinitions"] << { "name" => "log-router", "image" => "router", "essential" => true }
    definition["containerDefinitions"].first["dependsOn"] = [router]
    web, migrate = containers(run_step(definition)).values_at("web", "migrate")

    assert_equal [router, { "containerName" => "migrate", "condition" => "SUCCESS" }], web["dependsOn"]
    assert_equal [router], migrate["dependsOn"]
  end

  test "stops the deploy when the web container sets an entryPoint" do
    definition = task_definition
    definition["containerDefinitions"].first["entryPoint"] = %w[bin/docker-server]

    assert_nil run_step(definition)
  end

  test "stops the deploy when the task definition has no web container" do
    definition = task_definition
    definition["containerDefinitions"].first["name"] = "something-else"

    assert_nil run_step(definition)
  end

  private

  def task_definition
    {
      "family" => "app-staging-fg",
      "cpu" => "256",
      "memory" => "2048",
      "containerDefinitions" => [
        {
          "name" => "web",
          "image" => WEB_IMAGE,
          "essential" => true,
          "cpu" => 0,
          "portMappings" => [{ "containerPort" => 80, "hostPort" => 80, "protocol" => "tcp" }],
          "environment" => [{ "name" => "RAILS_ENV", "value" => "production" }],
          "logConfiguration" => { "logDriver" => "awslogs", "options" => { "awslogs-stream-prefix" => "ecs" } }
        }
      ]
    }
  end

  def containers(definition)
    definition["containerDefinitions"].index_by { _1["name"] }
  end

  # The step's result, or nil when the step fails.
  def run_step(definition)
    Dir.mktmpdir do |dir|
      rendered = File.join(dir, "rendered.json")
      output = File.join(dir, "github_output")
      File.write(rendered, JSON.generate(definition))
      env = { "RENDERED" => rendered, "RUNNER_TEMP" => dir, "GITHUB_OUTPUT" => output, "AWS_ECS_CONTAINER_NAME" => "web" }
      _out, _err, status = Open3.capture3(env, "bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", step_script)
      next unless status.success?

      JSON.parse(File.read(File.read(output)[/\Atask-definition=(.+)$/, 1]))
    end
  end

  def step_script
    @step_script ||= YAML.load_file(Rails.root.join(".github/workflows/cicd.yml"))
      .dig("jobs", "deploy-staging", "steps").find { _1["name"] == STEP_NAME }["run"]
  end
end
