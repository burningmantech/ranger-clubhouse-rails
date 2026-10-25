# frozen_string_literal: true

class MealInfo
  MEALS = {
    "all" => {
      title: "All Eats Meal Pass",
      description: "Congratulations, you qualify for three meals/day during the pre-event period, the event week, and post event week using your BMID!"
    },
    "pre" => {
      title: "Pre Event Meal Pass",
      description: "You qualify for three meals/day using your BMID during the Pre-Event period.<br>If you ranger a shift after the Pre-Event period, we'll give you a meal pog."
    },
    "post" => {
      title: "Post Event Meal Pass",
      description: "You qualify for three meals/day using your BMID during the Post-Event period.<br>If you ranger a shift in the Pre-event period or during the event week, we'll give you a meal pog."
    },
    "event" => {
      title: "Event Week Meal Pass",
      description: "You qualify for three meals/day using your BMID during the event week.<br>If you ranger a shift during Pre-Event period and Post-Event week, we'll give you a meal pog."
    },
    "pre+event" => {
      title: "Pre-Event and During Event Pass",
      description: "You qualify for three meals/day using your BMID during both the Pre-Event period and the event week itself.<br>If you ranger a shift during Post-Event, we'll give you a meal pog"
    },
    "event+post" => {
      title: "Event Week & Post Event Meal Pass",
      description: "You're eligible for three meals/day during both the event week and Post-Event periods with your BMID.<br>If you ranger a shift during Pre-Event, we'll give you a meal pog."
    },
    "pre+post" => {
      title: "Pre & Post Event Pass",
      description: "You're eligible for three meals/day during both the Pre-Event and Post-Event periods with your BMID..<br>If you ranger a shift during the Event week, we'll give you a meal pog."
    },
    "pogs" => {
      title: "Meal Pogs",
      description: "Every time you ranger a 6+ hour shift, we'll give you a meal pog good for one of the next three meals (breakfast, lunch, or dinner)."
    },
    "no-info" => {
      title: "Pending",
      description: "Meal information is not yet available."
    }
  }.freeze

  attr_reader :title, :description

  def initialize(event_info)
    meals = event_info.meals
    periods = []
    periods << "pre" if meals.pre
    periods << "event" if meals.event
    periods << "post" if meals.post

    type = determine_type(periods)
    meal_info = MEALS[type]

    @is_banked = false
    if meal_info
      @title = meal_info[:title]
      @description = meal_info[:description].html_safe
      @is_meal_pass = type == "all" || type == "event"
    else
      @title = "Unknown"
      @description = "Unknown meal type #{type}. This is a bug."
      @is_meal_pass = false
    end
  end

  def banked?
    @is_banked
  end

  def meal_pass?
    @is_meal_pass
  end

  private

  def determine_type(periods)
    if periods.length == 3
      "all"
    elsif periods.any?
      periods.join("+")
    else
      "pogs"
    end
  end
end
