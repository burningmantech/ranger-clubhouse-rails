# frozen_string_literal: true

require "test_helper"

class CertificationTest < ActiveSupport::TestCase
  # Every holder counts here, whatever their status: three people hold CPR, and
  # only two of them are still on the roster.
  test "total_people counts the certification's person records" do
    assert_equal 3, certification(:cpr).total_people
    assert_equal 0, certification(:wilderness_first_aid).total_people
  end
end
