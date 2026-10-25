class ChangePersonEventMayRequestStickersDefaultToFalse < ActiveRecord::Migration[8.0]
  def change
    change_column_default :person_event, :may_request_stickers, from: nil, to: false
  end
end
