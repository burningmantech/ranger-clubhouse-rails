# frozen_string_literal: true

# What the Clubhouse knows about Rangers' phone numbers: how many can receive a
# text, and who cannot.
#
# A number is only usable once its owner has confirmed the code texted to them,
# and it stops being usable if they reply STOP.
class RbsPhoneNumbers
  # One account status and the state of its phone numbers.
  Row = Struct.new(:status, :people, :numbers, :verified, :unverified, :stopped, keyword_init: true)

  class << self
    # A row per account status, in the order the statuses are listed elsewhere.
    def counts
      by_status = Person.live
                        .where.not(sms_number: [nil, ""])
                        .group(:status)
                        .pluck(Arel.sql("status"),
                               Arel.sql("COUNT(*)"),
                               Arel.sql("SUM(sms_verified)"),
                               Arel.sql("SUM(sms_stopped)"))
                        .index_by(&:first)
      people_by_status = Person.live.group(:status).count

      Person::LIVE_STATUSES.filter_map do |status|
        people = people_by_status[status].to_i
        next if people.zero?

        _, numbers, verified, stopped = by_status[status] || [status, 0, 0, 0]
        Row.new(status:, people:, numbers: numbers.to_i, verified: verified.to_i,
                unverified: numbers.to_i - verified.to_i, stopped: stopped.to_i)
      end
    end

    # People whose number is on file but was never confirmed.
    def unverified
      Person.live.where.not(sms_number: [nil, ""]).where(sms_verified: false).order(:callsign)
    end

    # People who asked us to stop texting them.
    def stopped
      Person.live.where.not(sms_number: [nil, ""]).where(sms_stopped: true).order(:callsign)
    end

    # How many numbers cannot receive a text right now.
    def unusable_count
      Person.live
            .where.not(sms_number: [nil, ""])
            .where(Person.arel_table[:sms_verified].eq(false)
                         .or(Person.arel_table[:sms_stopped].eq(true)))
            .count
    end
  end
end
