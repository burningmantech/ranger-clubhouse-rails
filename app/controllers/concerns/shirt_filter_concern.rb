# frozen_string_literal: true

# The shirt-kind filter machinery shared by the quartermaster shirt pages
# (Alpha Shirts, Potential Shirts): one select per ShirtTotals kind plus the
# "missing a size" checkbox, both normalised the same way, so a fix to either
# rule reaches every shirt page at once.
module ShirtFilterConcern
  extend ActiveSupport::Concern

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # The checkbox's "on" value. Unchecked posts "0", which is not blank and so
  # would draw a permanent chip -- it is normalised back to ALL instead.
  MISSING_ON = "1"

  private

  # One entry per shirt kind, in KINDS order, plus :missing last. Kind values
  # are accepted only as Strings: a hash-shaped query param (?tshirt[a]=b)
  # arrives as ActionController::Parameters, which would raise
  # UnfilteredParameters the moment a chip or export URL serialises it.
  def shirt_filter_params
    kinds = ShirtTotals::KINDS.to_h do |kind|
      value = params[kind[:param]]
      [kind[:param], (value.is_a?(String) ? value.presence : nil) || ALL]
    end

    kinds.merge(missing: params[:missing] == MISSING_ON ? MISSING_ON : ALL)
  end

  # Whether a person passes the three kind selects and the missing checkbox.
  # filter_params is the page's filter hash, which includes the
  # shirt_filter_params keys.
  def shirt_filters_match?(person, filter_params)
    return false if filter_params[:missing] == MISSING_ON && !ShirtTotals.missing_any_size?(person)

    ShirtTotals::KINDS.all? do |kind|
      title = filter_params[kind[:param]]
      title == ALL || ShirtTotals.title_for(person, kind[:reader]) == title
    end
  end
end
