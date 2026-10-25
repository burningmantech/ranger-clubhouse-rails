# frozen_string_literal: true

# Holds the state of the VC handle checker page: which handles have been
# checked, and which rules and handle types the results are narrowed to.
#
# The whole page round trips through the query string, so changing a rule
# re-checks every handle in the history rather than only the newest one. That
# keeps the Ember behavior, where toggling a rule immediately re-filtered
# results already on screen, without holding any state on the server.
class Vc::HandleCheckerForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "check"

  # Handles kept in the history. Every one is re-checked on every request.
  MAX_HISTORY = 25

  # Conflicts shown per checked handle. The eye rhyme rules can match
  # thousands of handles at once; conflicts sort most serious first, so the
  # cap only ever hides the least interesting ones.
  MAX_CONFLICTS = 50

  attribute :handle, :string, default: ""
  attribute :include_vintage, :boolean, default: true

  # Set by the form itself, so that clearing every checkbox is not mistaken
  # for a first visit with nothing chosen yet.
  attribute :configured, :boolean, default: false

  # Handle types checked on a first visit (HandleChecker#default_entity_types).
  attr_accessor :default_entity_types

  # Cleaned as they come in, so every reader can trust them. The page state
  # arrives from the query string, which may be hand-edited into any shape.
  def names=(values)
    @names = clean_list(values)
  end

  def rule_ids=(values)
    @rule_ids = clean_list(values)
  end

  def entity_types=(values)
    @entity_types = clean_list(values)
  end

  def self.from_params(params, default_entity_types:)
    # Anything but a hash under the scope -- ?check=x, ?check[]=x -- is ignored.
    values = params[PARAM_SCOPE]
    values = values.respond_to?(:to_unsafe_h) ? values.to_unsafe_h : {}
    form = new(values.slice("handle", "include_vintage", "configured", "names", "rule_ids", "entity_types"))
    form.default_entity_types = default_entity_types
    form
  end

  def persisted? = false

  # The newest handle first, then the history. Checking a handle already in
  # the history moves it back to the top rather than repeating it.
  def checked_names
    @checked_names ||= (Array(handle.to_s.strip.presence) + names)
                       .uniq { |name| name.downcase }
                       .first(MAX_HISTORY)
  end

  def names = @names || []

  def rule_ids
    return HandleChecker.default_rule_ids unless configured

    @rule_ids || []
  end

  def entity_types
    return Array(default_entity_types) unless configured

    @entity_types || []
  end

  # How the checker should narrow its results.
  def check_options = { rule_ids:, entity_types:, include_vintage: }

  # Keeps the current narrowing, drops the checked handles.
  def clear_history_params
    { PARAM_SCOPE => narrowing_params }
  end

  # Keeps the checked handles, drops the narrowing. Leaving out "configured"
  # is what puts the rules and handle types back to their defaults.
  def reset_narrowing_params
    { PARAM_SCOPE => { "names" => checked_names } }
  end

  # Narrowed means "differs from what a first visit shows" -- the default
  # rules and the default handle types.
  def rules_narrowed? = rule_ids.sort != HandleChecker.default_rule_ids.sort

  def types_narrowed? = entity_types.sort != Array(default_entity_types).sort

  def narrowed? = rules_narrowed? || types_narrowed? || !include_vintage

  private

  def narrowing_params
    {
      "configured" => "1",
      "include_vintage" => include_vintage ? "1" : "0",
      "rule_ids" => rule_ids,
      "entity_types" => entity_types
    }
  end

  def clean_list(values)
    Array(values).flatten.filter_map { |value| value.to_s.strip.presence }.uniq
  end
end
