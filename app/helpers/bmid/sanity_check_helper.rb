# frozen_string_literal: true

# Tile labels and the check filter for BMID > Sanity Check. (Compact form:
# Bmid is the model class, not a module.)
module Bmid::SanityCheckHelper
  # Presentation per check, keyed by BmidSanityCheckReport::CHECK_KEYS (the
  # controller test asserts the two stay in sync). label reads on the filter
  # select and empty states; short_label fits the tiles, the filter chip, and
  # the table's check badges.
  CHECK_META = {
    shifts_before_access_date: {
      label: "Shifts before SAP access date",
      short_label: "Before SAP date",
      icon: "calendar-xmark"
    },
    shifts_before_submitted_wap: {
      label: "Shifts before submitted SAP access date",
      short_label: "Before submitted SAP",
      icon: "paper-plane"
    },
    shifts_no_wap: {
      label: "Pre-event shifts with no SAP",
      short_label: "No SAP",
      icon: "id-card-clip"
    },
    spt_before_box_office: {
      label: "SPT access before box office opens",
      short_label: "SPT early access",
      icon: "ticket"
    }
  }.freeze

  # Fetch raises on an unknown key on purpose: the controller has already
  # validated user input against the report's CHECK_KEYS, so a miss here is a
  # programmer error, not bad input.
  def sanity_check_meta(check)
    CHECK_META.fetch(check)
  end

  # At most one filter on this page, so at most one chip.
  def sanity_check_filter_chips(check)
    return [] unless check

    [{ label: "Check: #{sanity_check_meta(check)[:short_label]}",
       url: bmid_sanity_check_path }]
  end

  def sanity_check_filter_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      CHECK_META.map { |key, meta| [meta[:label], key.to_s] }
  end
end
