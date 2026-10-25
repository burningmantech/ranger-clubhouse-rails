# frozen_string_literal: true

# HQ window suggested-task ("todo") vocabulary — the task keys and their
# user-visible checklist chip labels.
#
# Ported from the Ember clubhouse/constants/hq-todo.js (staged in
# port/constants/hq-todo.js). Keys are the kebab-case HQ_TODO_* string
# constants underscored into symbols; LABELS follows HqTodoLabels, reworded
# into this project's volunteer terminology and copy style (verb-phrase chips,
# em dash clause separators, no "(s)").
# The upstream HqTodoTask class (per-chip completed/ignore/blink
# state) is client-side checklist state and belongs to the hq-shift Stimulus
# controller, not this module.
module HqTodo
  COLLECT_RADIO = :collect_radio
  DELIVERY_MESSAGE = :delivery_message
  END_SHIFT = :end_shift
  ISSUE_RADIO = :issue_radio
  MEAL_POG = :meal_pog
  MEAL_POG_NONE = :no_meal_pog
  NO_RADIO = :no_radio
  START_SHIFT = :start_shift
  VERIFY_TIMESHEET = :verify_timesheet
  OFF_SITE = :off_site
  COLLECT_RADIO_IF_DONE = :collect_radio_if_done

  LABELS = {
    COLLECT_RADIO => "Collect Radio",
    COLLECT_RADIO_IF_DONE => "Collect Radio (if done rangering)",
    DELIVERY_MESSAGE => "Deliver Messages",
    END_SHIFT => "End The Shift",
    ISSUE_RADIO => "Check Out Radio",
    MEAL_POG => "Issue Meal Pog (if qualified)",
    MEAL_POG_NONE => "No Meal Pog — Has Meal Pass",
    NO_RADIO => "On Burn Perimeter — may not need a radio",
    START_SHIFT => "Start A Shift",
    VERIFY_TIMESHEET => "Review Timesheet",
    OFF_SITE => "No more upcoming shifts — ask if finished rangering"
  }.freeze
end
