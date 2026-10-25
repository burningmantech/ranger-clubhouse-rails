# frozen_string_literal: true

# The filters and the delete confirmation on Pog Administration
# (Pogs::AdministrationController).
module Pogs::AdministrationHelper
  # Each filter's name, for its field and its chip alike, so the two read the same.
  POGS_ADMINISTRATION_FILTER_LABELS = {
    person_callsign: "Recipient", issued_by_id: "Issued By", day: "Day", pog: "Type", status: "Status"
  }.freeze

  def pogs_administration_filter_label(key) = POGS_ADMINISTRATION_FILTER_LABELS.fetch(key)

  # issuer_ids: every issuer of the year's pogs; issuers: those still on file,
  # {id => Person}. One whose person row is gone keeps an option ("Deleted #12"),
  # so a filter on them shows in the select and survives the next Apply. By
  # callsign whatever its case, deleted ones last.
  def pogs_administration_issuer_options(issuer_ids, issuers)
    options = issuer_ids.map { |id| [person_display_name(issuers[id], id), id] }
                        .sort_by { |name, id| [issuers[id] ? 0 : 1, name.downcase] }
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + options.map { |name, id| [name, id.to_s] }
  end

  # days: the dates the year's pogs were issued on, in order.
  def pogs_administration_day_options(days)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + days.map { |date| [wday_month_day_format(date), date.iso8601] }
  end

  # pog_types: the types the year holds, so no choice can only come back empty.
  def pogs_administration_type_options(pog_types)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      pog_types.map { |pog| [PersonPog::POG_LABELS.fetch(pog), pog] }
  end

  # statuses: the PogFilterForm status values the year holds.
  def pogs_administration_status_options(statuses)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      statuses.map { |status| [PersonPog::STATUS_LABELS.fetch(status), status] }
  end

  # The edit page's delete confirmation. The message lives in an attribute, so
  # the time is plain text: datetime_format's span would print as markup there.
  def pogs_administration_delete_confirm(pog, recipient)
    { title: "Delete Pog",
      message: "Delete this #{pog.pog_label} issued to #{recipient} on " \
               "#{pog.issued_at.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)}? This cannot be undone.",
      confirm_label: "Delete Pog", variant: :error }
  end

  # One chip per active filter, its value in the words its field uses. Each
  # chip's URL drops that filter and keeps the rest, and the year.
  def pogs_administration_filter_chips(form, issuers, year)
    value_label = lambda do |key, value|
      case key
      when :issued_by_id then person_display_name(issuers[value.to_i], value)
      when :day then wday_month_day_format(Date.iso8601(value))
      when :pog then PersonPog::POG_LABELS.fetch(value)
      when :status then PersonPog::STATUS_LABELS.fetch(value)
      else value
      end
    end

    filter_chips(form.active, POGS_ADMINISTRATION_FILTER_LABELS, value_label:) do |remaining, _key|
      pogs_administration_path(year:, PogFilterForm::PARAM_SCOPE => remaining)
    end
  end
end
