# frozen_string_literal: true

# View helper for the Convert Alphas page: the one badge that names a mentor
# verdict.
#
# The wording matches MentorHelper::RESULT_LABELS -- the words the pages that
# record these verdicts use -- rather than upstream's raw database values
# ("pass", "self-bonk").
#
# The colours are MentorHelper::MENTOR_STATUS's, with one deliberate difference:
# a self-bonk is amber here, not red. It shares its destination with a bonk, so
# the destination cannot tell the two apart, and a mentor reading this page is
# entitled to see at a glance which Alphas chose to stop.
module Mentoring::AlphasConvertHelper
  VERDICT_BADGES = {
    PersonMentor::STATUS_PASS => { label: "Passed", variant: :success, icon: "circle-check" },
    PersonMentor::STATUS_BONK => { label: "Bonked", variant: :error, icon: "circle-xmark" },
    PersonMentor::STATUS_SELF_BONK => { label: "Self-bonked", variant: :warning, icon: "circle-minus" }
  }.freeze

  # A verdict this page cannot act on should still be legible rather than blank,
  # so an unrecognised value is shown as itself.
  def alpha_verdict_badge(verdict)
    badge = VERDICT_BADGES[verdict]
    return ui_badge(verdict.to_s, :secondary) unless badge

    ui_badge badge[:label], badge[:variant], icon: badge[:icon], icon_type: :solid
  end
end
