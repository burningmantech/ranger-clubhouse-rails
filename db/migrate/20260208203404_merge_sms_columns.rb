class MergeSmsColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :person, :sms_number, :string
    add_column :person, :sms_stopped, :boolean, default: false, null: false
    add_column :person, :sms_code, :string
    add_column :person, :sms_verified, :boolean, default: false, null: false

    transfer_sms_column(nil, false)
    transfer_sms_column("verified", true)
    transfer_sms_column("stopped", true)
    Person.update_all("sms_code = null")
  end

  private

  def transfer_sms_column(suffix, is_bool)
    old = suffix ? "sms_on_playa_#{suffix}" : "sms_on_playa"
    new_column = suffix ? "sms_#{suffix}" : "sms_number"

    if is_bool
      Person.update_all("sms_#{suffix} = #{old}")
    else
      Person.where("#{old} is not null or #{old} != ''").update_all("#{new_column} = #{old}")
    end

    Person.where("(sms_off_playa is not null or sms_off_playa != '') and (sms_on_playa is  null or sms_on_playa = '')").update_all("#{new_column} = #{old}")
  end

end
