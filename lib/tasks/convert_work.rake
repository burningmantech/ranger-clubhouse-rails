# lib/tasks/convert_work.rake
# Rake task to convert slot and timesheets from 2025 to 2026

namespace :dev do
  desc "Convert to slots & timesheets to 2026"
  task work_2026: :environment do
    Survey.where(year: 2025).update_all(year: 2026)
    slots = Slot.where(begins_year: 2025)

    slots.each do |slot|
      slot.begins = slot.begins.change(year: 2026)
      slot.begins_year = 2026
      slot.begins_time = slot.begins.to_i

      slot.ends = slot.ends.change(year: 2026)
      slot.ends_time = slot.ends.to_i
      slot.save!(touch: false)
    end

    credits = PositionCredit.where(start_year: 2025)

    credits.each do |credit|
      credit.start_time = credit.start_time.change(year: 2026)
      credit.end_time = credit.end_time.change(year: 2026)
      credit.save!(touch: false)
    end

    entries = Timesheet.where("year(on_duty)=?", 2025)
    entries.each do |entry|
      entry.on_duty = entry.on_duty.change(year: 2026)
      entry.off_duty = entry.off_duty.change(year: 2026)
      entry.save!(touch: false, validate: false)
    end
  end
end
