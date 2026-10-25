class ChangeClientRouteToPageVist < ActiveRecord::Migration[8.1]
  def up
    ActionLog.where(event: "client-route").update_all(event: "page-visit")
  end

  def down
    ActionLog.where(event: "page-visit").update_all(event: "client-route")
  end
end
