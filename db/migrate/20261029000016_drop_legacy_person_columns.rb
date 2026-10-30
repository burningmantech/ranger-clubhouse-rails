# frozen_string_literal: true

# Columns Clubhouse 2 left behind on person:
# - the eight sms_on_playa / sms_off_playa columns, merged into sms_number and
#   friends by MergeSmsColumns (2026-02); nine rows that merge passed over are
#   copied first, then the eight go;
# - is_bouncing, replaced by email_suppression (copied by
#   CopyBouncingFlagsToEmailSuppression, which runs before this).
# shirt_size and shirt_style stay: 1,921 people have a bare legacy size and no
# swag row, and which shirt style a bare "L" means is the quartermaster's call.
class DropLegacyPersonColumns < ActiveRecord::Migration[8.1]
  def change
    up_only do
      execute <<~SQL.squish
        UPDATE person
           SET sms_number = COALESCE(NULLIF(sms_on_playa, ''), NULLIF(sms_off_playa, '')),
               sms_verified = IF(NULLIF(sms_on_playa, '') IS NULL, sms_off_playa_verified, sms_on_playa_verified),
               sms_stopped = IF(NULLIF(sms_on_playa, '') IS NULL, sms_off_playa_stopped, sms_on_playa_stopped)
         WHERE (sms_number IS NULL OR sms_number = '')
           AND (NULLIF(sms_on_playa, '') IS NOT NULL OR NULLIF(sms_off_playa, '') IS NOT NULL)
      SQL
    end

    remove_column :person, :sms_off_playa, :string
    remove_column :person, :sms_on_playa, :string
    remove_column :person, :sms_off_playa_stopped, :boolean, default: false, null: false
    remove_column :person, :sms_on_playa_stopped, :boolean, default: false, null: false
    remove_column :person, :sms_off_playa_verified, :boolean, default: false, null: false
    remove_column :person, :sms_on_playa_verified, :boolean, default: false, null: false
    remove_column :person, :sms_off_playa_code, :string, limit: 16
    remove_column :person, :sms_on_playa_code, :string, limit: 16
    remove_column :person, :is_bouncing, :boolean, default: false, null: false
  end
end
