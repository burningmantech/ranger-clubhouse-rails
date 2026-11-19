# frozen_string_literal: true

# Why a mark was made. "manual": someone marked the person at the HQ window or
# on their person page. "automatic": the on-site cleanup marked them off site
# once nothing tied them to the site, and dated the mark at their last activity.
# Every existing row was made by hand, or by a yearly reset an admin ran, and
# starts as manual; RedateBulkOffSiteMarks sorts out the resets.
class AddReasonToPersonOnSite < ActiveRecord::Migration[8.1]
  def change
    add_column :person_on_site, :reason, "enum('manual','automatic')", null: false, default: "manual"
  end
end
