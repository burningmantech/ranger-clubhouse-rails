# frozen_string_literal: true

# One thing a sanity check flagged: always a person, sometimes a team or
# position they hold or are missing.
#
# target_id is what the repair acts on and what makes a row selectable on its
# own -- a person missing two team positions is two findings, and fixing one of
# them must not fix the other. Person-grain checks leave it nil.
#
# group_id / group_label put a row under a heading on the check's page (the
# deactivated position or team it belongs to). detail carries whatever else
# that check's table shows.
PositionSanityCheck::Finding = Struct.new(
  :person_id, :callsign, :status, :target_id, :target_label,
  :group_id, :group_label, :detail,
  keyword_init: true
) do
  # What the checkbox carries and what the repair matches on. A pair for
  # target-grain checks, the bare person id otherwise.
  def key = target_id ? "#{person_id}:#{target_id}" : person_id.to_s
end
