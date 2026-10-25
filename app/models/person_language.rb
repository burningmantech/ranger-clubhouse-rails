# frozen_string_literal: true

class PersonLanguage < ApplicationRecord
  self.table_name = "person_language"

  # Proficiency levels
  PROFICIENCY_UNKNOWN = "unknown"
  PROFICIENCY_BASIC = "basic"
  PROFICIENCY_INTERMEDIATE = "intermediate"
  PROFICIENCY_FLUENT = "fluent"

  PROFICIENCY_TYPES = [
    PROFICIENCY_UNKNOWN, PROFICIENCY_BASIC, PROFICIENCY_INTERMEDIATE, PROFICIENCY_FLUENT
  ].freeze

  PROFICIENCY_LABELS = {
    PROFICIENCY_UNKNOWN => "Not Stated",
    PROFICIENCY_BASIC => "Basic",
    PROFICIENCY_INTERMEDIATE => "Intermediate",
    PROFICIENCY_FLUENT => "Fluent"
  }.freeze

  PROFICIENCY_OPTIONS = [
    ["Not Stated", PROFICIENCY_UNKNOWN],
    ["Basic: You can answer basic questions using some common phrases and words.", PROFICIENCY_BASIC],
    ["Intermediate: You can hold a causal conversation.", PROFICIENCY_INTERMEDIATE],
    ["Fluent/Native: You can have an in-depth conversation.", PROFICIENCY_FLUENT]
  ].freeze

  LANGUAGE_NAME_CUSTOM = "custom"

  # Common languages encountered on playa
  COMMON_PLAYA_LANGUAGES = [
    "American Sign Language",
    "Arabic",
    "Chinese (Mandarin)",
    "Cantonese",
    "Danish",
    "Dutch",
    "English",
    "Farsi",
    "French",
    "German",
    "Hebrew",
    "Hindi",
    "Italian",
    "Japanese",
    "Norwegian",
    "Polish",
    "Portuguese",
    "Punjabi",
    "Romanian",
    "Russian",
    "Spanish",
    "Swedish",
    "Tagalog",
    "Urdu"
  ].freeze

  LANGUAGE_NAME_OPTIONS = [
    ["--", ""],
    *COMMON_PLAYA_LANGUAGES,
    ["Something else", LANGUAGE_NAME_CUSTOM]
  ].freeze

  belongs_to :person

  strip_attributes only: [:language_custom]

  validates :language_name, presence: true, length: { maximum: 32 },
            uniqueness: {
              scope: %w[person_id language_name language_custom],
              message: "The language has already been listed."
            }
  validates :language_custom, presence: true, length: { maximum: 32 }, if: -> { language_name == LANGUAGE_NAME_CUSTOM }

  validates :proficiency, presence: true, inclusion: { in: PROFICIENCY_TYPES }

  before_save :clear_language_custom_if_not_custom

  def self.find_for_query(query = {})
    query = query.symbolize_keys

    scope = self
    scope = scope.where(person_id: query[:person_id]) if query[:person_id]
    rows = scope.all

    rows.sort! do |a, b|
      if a.person_id == b.person_id
        a.actual_name.casecmp(b.actual_name)
      else
        a.person_id <=> b.person_id
      end
    end

    rows
  end

  def actual_name
    language_name == LANGUAGE_NAME_CUSTOM ? language_custom : language_name
  end

  def proficiency_label
    PROFICIENCY_LABELS[proficiency] || proficiency
  end

  def is_custom?
    language_name == LANGUAGE_NAME_CUSTOM
  end

  private

  def clear_language_custom_if_not_custom
    self.language_custom = nil if language_name != LANGUAGE_NAME_CUSTOM && language_custom.present?
  end
end
