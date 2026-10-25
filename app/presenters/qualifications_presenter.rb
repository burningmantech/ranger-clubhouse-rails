# frozen_string_literal: true

# How the Qualifications page reads a TicketsAndProvisionsProgress: which rows
# show, how each goal and section stands, and the one row to sign up for next.
#
# A goal is one thing a Ranger can end up with. Its rows are tiers (a Staff
# Credential supersedes a Special Price Ticket) or alternative paths (the two Wet
# Spot Access thresholds), so a goal stands as well as its best row.
class QualificationsPresenter
  GOALS = {
    ticket: %i[spt staff_credential],
    meal_pass: %i[event_week_eats all_eats],
    shower_pog: %i[shower_pog],
    shower_access: %i[shower_access_event_week shower_access_entire_event],
    t_shirt: %i[t_shirt],
    long_sleeve_shirt: %i[long_sleeve_shirt]
  }.freeze

  SECTIONS = {
    tickets: %i[ticket],
    meal_passes: %i[meal_pass],
    ranger_clothing: %i[t_shirt long_sleeve_shirt],
    showers: %i[shower_pog shower_access]
  }.freeze

  # Upper tiers stay worth suggesting after a lower tier has secured their goal.
  UPGRADES = %i[staff_credential all_eats].freeze

  # A closed row cannot be earned this year: its counter can no longer grow. The
  # two folds rank it differently. A goal stands as well as its best row, and an
  # open path beats a closed one, since the goal can still be earned through it;
  # a section shows its worst goal, and there a closed goal ranks above one that
  # needs sign-ups -- nothing can be done about it, so a section with any open
  # goal still asks for sign-ups.
  GOAL_RANK = %i[earned on_track needs_sign_ups closed].freeze
  SECTION_RANK = %i[needs_sign_ups closed on_track earned].freeze

  # others: how many more rows the same sign-ups would also earn.
  NextStep = Struct.new(:item, :others)

  def initialize(items, shiny_penny:)
    @items = items
    @shiny_penny = shiny_penny
  end

  def [](key) = @items.fetch(key)

  def shiny_penny? = @shiny_penny

  # A lower tier drops out once its upper tier is earned, as does the combined Wet
  # Spot Access path once the Event Week path is.
  def visible?(key)
    case key
    when :spt then !@items[:staff_credential].has_earned
    when :event_week_eats then !@items[:all_eats].has_earned
    when :shower_access_entire_event then !@items[:shower_access_event_week].has_earned
    else true
    end
  end

  def state(key)
    item = @items.fetch(key)
    if item.has_earned
      :earned
    elsif item.expected_to_earn
      :on_track
    elsif item.closed
      :closed
    else
      :needs_sign_ups
    end
  end

  # The worst goal in the section, so an earned goal never hides an open one. nil
  # when the section holds no goals: Ranger Clothing for a Shiny Penny.
  def section_state(section)
    (SECTIONS.fetch(section) & goals).map { |goal| goal_state(goal) }.min_by { |state| SECTION_RANK.index(state) }
  end

  def goal_counts = goals.map { |goal| goal_state(goal) }.tally

  def all_earned? = goals.all? { |goal| goal_state(goal) == :earned }

  # Something is unearned and none of it can still be earned this year.
  def closed_out?
    states = goals.map { |goal| goal_state(goal) }
    states.include?(:closed) && (states - %i[closed earned]).empty?
  end

  # The smallest ask: the row short of sign-ups by the fewest hours or credits, in a
  # goal not yet secured or as an upper tier. Credits and hours count as one unit,
  # near enough for most shifts, so 18 hours to a T-Shirt beats 122 hours to a meal
  # pass even when the meal pass is further along. A secured goal's other rows never
  # count, and neither does a hidden row, since rows hide only once their goal is
  # earned. nil when nothing is left to sign up for.
  def next_step
    rows = goals.flat_map { |goal| goal_state(goal) == :needs_sign_ups ? GOALS[goal] : GOALS[goal] & UPGRADES }
    # @items order, not goal order, breaks ties between equally small asks.
    wanted = (@items.keys & rows).select { |key| state(key) == :needs_sign_ups }
    key = wanted.min_by { |candidate| @items[candidate].shortfall }
    return unless key

    item = @items[key]
    others = wanted.count do |other|
      other != key && @items[other].counter == item.counter && @items[other].threshold == item.threshold
    end
    NextStep.new(item, others)
  end

  private

  def goals = @shiny_penny ? GOALS.keys - SECTIONS.fetch(:ranger_clothing) : GOALS.keys

  def goal_state(goal) = GOALS.fetch(goal).map { |key| state(key) }.min_by { |state| GOAL_RANK.index(state) }
end
