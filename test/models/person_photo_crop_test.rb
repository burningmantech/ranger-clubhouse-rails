# frozen_string_literal: true

require "test_helper"
require "vips"

class PersonPhotoCropTest < ActiveSupport::TestCase
  # apply_crop_transformation must reproduce the CropperJS mapping
  #   q = L·p + T, T = center + (e, f) − L·center
  # Uses a Vips xyz image (pixel value = its own coordinates) so an output
  # pixel directly reports which source point it was sampled from.
  test "crop extraction reproduces a rotated, scaled CropperJS transform" do
    width, height = 1000, 800
    source = Vips::Image.xyz(width, height)

    # 90° clockwise rotation at scale 0.5625, natural center pinned to canvas center:
    # CSS matrix(a, b, c, d, e, f) = (s·cos, s·sin, −s·sin, s·cos, e, f)
    s = 0.5625
    params = {
      scale_x: 0.0, skew_x: s, skew_y: -s, scale_y: 0.0,
      translate_x: PersonPhoto::PROFILE_WIDTH / 2.0 - width / 2.0,
      translate_y: PersonPhoto::PROFILE_HEIGHT / 2.0 - height / 2.0
    }

    result = PersonPhoto.new.send(:apply_crop_transformation, source, params)

    assert_equal PersonPhoto::PROFILE_WIDTH, result.width
    assert_equal PersonPhoto::PROFILE_HEIGHT, result.height

    # Canvas center maps back to the natural-image center
    assert_in_delta width / 2.0, result.getpoint(175, 225)[0], 2.0
    assert_in_delta height / 2.0, result.getpoint(175, 225)[1], 2.0

    # Hand-computed: canvas (275, 125) pulls from natural (322.22, 222.22)
    # (q − center offset (100, −100) rotated back by −90° and unscaled)
    assert_in_delta 322.22, result.getpoint(275, 125)[0], 2.0
    assert_in_delta 222.22, result.getpoint(275, 125)[1], 2.0
  end

  test "extreme scale values are rejected even when rotated" do
    source = Vips::Image.xyz(100, 100)
    # scale 20 hidden in rotation terms: column norm √(14²+14²) ≈ 19.8… use 15/15 → 21.2
    params = { scale_x: 15.0, skew_x: 15.0, skew_y: -15.0, scale_y: 15.0 }

    error = assert_raises(StandardError) do
      PersonPhoto.new.send(:apply_crop_transformation, source, params)
    end
    assert_match(/Scale values exceed/, error.message)
  end
end
