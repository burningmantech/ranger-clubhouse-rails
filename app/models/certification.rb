# frozen_string_literal: true

class Certification < ApplicationRecord
  self.table_name = "certification"

  has_many :person_certifications, class_name: "PersonCertification", dependent: :delete_all

  validates :title, presence: true
  validates :sl_title, presence: true, if: :on_sl_report?

  scope :on_sl_report, -> { where(on_sl_report: true) }

  def self.find_for_query(query = {})
    sql = all
    sql = sql.where(on_sl_report: query[:on_sl_report]) if query.key?(:on_sl_report)
    sql
  end

  def self.find_by_title(title)
    find_by(title: title)
  end

  def total_people
    person_certifications.count
  end
end
