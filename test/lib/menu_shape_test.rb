# frozen_string_literal: true

require "test_helper"

# A section holds links under :items; :sections is only for nested sections.
# A link hash filed under :sections renders nothing (Mentoring lost five links
# that way on 2026-09-30), so every menu definition is walked here.
class MenuShapeTest < ActiveSupport::TestCase
  test "links live under :items, never under :sections" do
    Menus.constants.each do |name|
      definition = Menus.const_get(name)
      next unless definition.is_a?(Hash) && definition[:sections]

      check_sections(definition[:sections], "Menus::#{name}")
    end
  end

  private

  def check_sections(sections, where)
    sections.each do |section|
      refute section.key?(:path), "#{where}: #{section[:title].inspect} is a link filed under :sections"
      check_sections(section[:sections] || [], "#{where} › #{section[:title]}")
    end
  end
end
