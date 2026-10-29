# frozen_string_literal: true

# The date and status cells of Person › Teams & Positions History
# (Person::MembershipHistoryController), spelled once for both tables and for
# the About card that quotes them.
module Person::MembershipHistoryHelper
  NOT_RECORDED = "Not recorded"

  def membership_tracking_began = mdy_format(MembershipHistory::TRACKING_BEGAN)

  def membership_before_tracking_label = "Before #{membership_tracking_began}"

  def membership_began_cell(spell)
    return membership_unrecorded_cell(membership_before_tracking_label) if spell.before_tracking?

    spell.began_on ? mdy_format(spell.began_on) : membership_unrecorded_cell(NOT_RECORDED)
  end

  def membership_ended_cell(spell)
    return mdy_format(spell.ended_on) if spell.ended_on

    spell.current ? "—" : membership_unrecorded_cell(NOT_RECORDED)
  end

  # Plain text while the spell continues; a badge marks the ones that ended.
  def membership_status_cell(spell, now_label, past_label)
    spell.current ? now_label : ui_badge(past_label, :secondary, icon: "circle-minus")
  end

  private

  def membership_unrecorded_cell(text) = tag.span(text, class: "text-stone-muted")
end
