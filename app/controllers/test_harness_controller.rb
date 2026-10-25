# frozen_string_literal: true

# Test-only controller providing isolated fixtures for system tests.
# Guarded by Rails.env.test? — routes are only defined in test env.
class TestHarnessController < ApplicationController
  skip_before_action :require_authentication

  def autocomplete_fixture
    render layout: false
  end

  def search_bar_fixture
    render layout: false
  end
end
