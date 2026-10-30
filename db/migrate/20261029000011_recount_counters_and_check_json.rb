# frozen_string_literal: true

# Two counters had drifted from the rows they count: slot.signed_up on 302
# slots (all but two from before 2019) and pod.person_count on 191 pods. Both
# are recounted once here; PersonSlot and PersonPod now keep them right when a
# row goes, which is the path Person's deletion takes.
#
# The three newer years_* JSON caches on person gain the json_valid check the
# other four already have; every row passes it.
class RecountCountersAndCheckJson < ActiveRecord::Migration[8.1]
  def change
    up_only do
      execute "UPDATE slot SET signed_up = (SELECT COUNT(*) FROM person_slot WHERE person_slot.slot_id = slot.id)"
      execute "UPDATE pod SET person_count = (SELECT COUNT(*) FROM person_pod WHERE person_pod.pod_id = pod.id)"
    end

    %w[years_of_service years_of_awards years_of_signups].each do |column|
      add_check_constraint :person, "json_valid(`#{column}`)", name: column
    end
  end
end
