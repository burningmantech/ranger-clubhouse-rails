# frozen_string_literal: true

require "test_helper"

class AssetAttachmentTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 14, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)

    ActionLog.delete_all
    AssetAttachment.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "parent type must be present and supported" do
    attachment = AssetAttachment.new(parent_type: "Badge", description: "")

    assert_not attachment.valid?
    assert_includes attachment.errors[:parent_type], "Parent type is not included in the list."
    assert_includes attachment.errors[:description], "Description can't be blank."
  end

  test "find_all orders by description and alias matches" do
    alpha = AssetAttachment.create!(id: 1, parent_type: AssetAttachment::RADIO, description: "Alpha")
    zulu = AssetAttachment.create!(id: 2, parent_type: AssetAttachment::VEHICLE, description: "Zulu")

    assert_equal [alpha.id, zulu.id], AssetAttachment.find_all.pluck(:id)
    assert_equal [alpha.id, zulu.id], AssetAttachment.findAll.pluck(:id)
  end
end
