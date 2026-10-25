# frozen_string_literal: true

module YearHelper
  def years_breakdown(person)
    render partial: "common/years_breakdown", locals: { person: }
  end

  def year_range(years)
    return content_tag(:span, "none", class: "text-stone-muted") if years.blank?

    years.chunk_while { |i, j| j == i + 1 }
         .map { |chunk| (chunk.size == 1) ? chunk.first.to_s : "#{chunk.first} - #{chunk.last}" }
         .join(", ")
  end
end
