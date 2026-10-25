# frozen_string_literal: true

# Sets environment variables for one block, then puts back what each held
# before, and unsets the ones that were not set.
module EnvTestHelper
  def with_env(values)
    previous = values.keys.index_with { |key| ENV.fetch(key, nil) }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
