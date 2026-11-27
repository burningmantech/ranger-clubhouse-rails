# frozen_string_literal: true

# Capybara empties Chrome after every system test, and 3.40.0, its newest release, ends that reset with
#
#   Storage.clearDataForOrigin(origin: "*", storageTypes: "cookies,local_storage")
#
# which Chrome up to 157 took as "every site": all cookies, local storage and session storage. Chrome 158
# reads the origin as a URL and refuses "*" ("invalid argument: * is not a valid URL"), so each system test
# passed its assertions and then errored in teardown. Upstream: teamcapybara/capybara#2865, open on
# 2026-11-25 with two fixes proposed and none released.
#
# Prepended to Capybara's Chrome driver (test/application_system_test_case.rb), this lets the call go
# through, so a Chrome that still takes "*" is emptied exactly as before, and steps in when Chrome
# refuses it. All cookies then go in one command. Storage has no every-site command, so it goes site by
# site, for each one in the tab's history. Chrome keeps the last 50 pages a tab loaded, which takes in
# both hosts the suite uses (127.0.0.1, and localhost for the passkey tests), and on Chrome 158 clearing
# a site's local storage this way empties its session storage with it.
#
# What "*" covered and this does not: storage on a site that only a second window visited (the reset has
# closed that window, and its history, by now), or that the tab left more than 50 pages ago.
#
# test/system/browser_reset_test.rb is the check. Delete this file and its prepend once a Capybara
# release stops sending "*": that test passes without them from then on.
module ChromeResetWithoutWildcardOrigin
  private

  def execute_cdp(cmd, params = {})
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError
    raise unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
    return unless params[:storageTypes].to_s.include?("local_storage")

    visited_origins.each { |origin| super("Storage.clearDataForOrigin", origin:, storageTypes: "local_storage") }
  end

  def visited_origins
    execute_cdp("Page.getNavigationHistory").fetch("entries").filter_map { |entry| http_origin(entry["url"]) }.uniq
  end

  # nil for about:blank, a data: URL, Chrome's own error page: nothing there to clear.
  def http_origin(url)
    uri = URI.parse(url)
    uri.origin if uri.is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    nil
  end
end
