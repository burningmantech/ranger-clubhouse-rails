# frozen_string_literal: true

# Filter chips and bucket vocabulary for the Eventree export page
# (/bmid/export).
module Bmid::ExportHelper
  # The problem buckets, in display order: each key names the disclosure's
  # words and badge colour. The controller derives its accumulator from these
  # keys, so the bucket list has exactly one home.
  BUCKETS = {
    do_not_print: { label: "Do Not Print", variant: :warning,
                    reason: "The badge status says not to print these." },
    issues: { label: "Issues", variant: :error,
              reason: "These badges have problems to resolve before printing." },
    unusual: { label: "Unusual Person Status", variant: :warning,
               reason: "These people hold a status outside the printable set." },
    submitted: { label: "Already Submitted", variant: :secondary,
                 reason: "These badges already went to the printer." }
  }.freeze

  # A bucket disclosure lists this many callsigns before deferring to the
  # manage roster: the whole category can land in one bucket (the submitted
  # category, late in the season), and a collapsed list of thousands of links
  # still ships in the page.
  BUCKET_PREVIEW_LIMIT = 50

  # One chip per active filter: the category once it is not the default, and
  # the search text. Same shape as bmid_manage_filter_chips.
  def bmid_export_filter_chips(q, base)
    active = {}
    category = base[:filter]
    active[:filter] = category unless category == BmidManagement::DEFAULT_FILTER
    active[:q] = q if q.present?

    labels = { filter: "Category", q: "Search" }

    filter_chips(active, labels, value_label: Bmid::ManageHelper::BMID_CHIP_VALUE) do |remaining|
      bmid_export_path(base.except(:filter).merge(remaining))
    end
  end
end
