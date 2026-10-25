# frozen_string_literal: true

module Person::SwagHelper
  SWAG_ROW_LABELS = {
    Swag::TYPE_DEPT_PATCH => "Ranger Service Patch",
    Swag::TYPE_DEPT_PIN   => "Ranger Service Pin",
    Swag::TYPE_ORG_PATCH  => "Org Service Patch",
    Swag::TYPE_ORG_PIN    => "Org Service Pin",
    Swag::TYPE_OTHER      => "Other Swag"
  }.freeze

  def swag_type_label(swag)
    return "-" if swag.nil?
    return ShirtHelper::SHIRT_TYPE_LABELS[swag.shirt_type] || "Shirt" if swag.type == Swag::TYPE_DEPT_SHIRT

    SWAG_ROW_LABELS[swag.type] || swag.type.to_s.titleize
  end
end
