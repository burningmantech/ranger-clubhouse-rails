# frozen_string_literal: true

module UrlHelper
  def ext_link(title, url, options = {})
    options[:rel] = "noopener noreferrer"
    options[:target] = "_blank"
    options[:class] = "inline-block hover:underline #{options[:class]}".squish
    link_to "#{title}#{fa_icon "arrow-up-right-from-square".html_safe, :solid, start: 2 }".html_safe, url, options
  end

  # A browser link to a Salesforce record. This is Burning Man's Salesforce org
  # front door, not the API instance_url the OAuth handshake hands back.
  #
  # @param record_id [String] the Salesforce record id (an SFUID, a Ranger__c id)
  # @return [String] the record's URL
  def salesforce_record_url(record_id)
    "https://burningman.my.salesforce.com/#{record_id}"
  end

  # Appends search parameters to a given URL.
  #
  # @param base_url [String] The original URL (may include existing query params)
  # @param params [Hash] A hash of parameters to add or override
  # @return [String] The URL with the new query string applied
  def append_query_params(base_url, params = {})
    uri = URI.parse(base_url)

    # Parse existing query parameters into a Hash
    existing_params = Rack::Utils.parse_nested_query(uri.query)

    # Merge with the new ones (new keys override old ones)
    merged_params = existing_params.merge(params)

    # Encode back into a query string
    uri.query = Rack::Utils.build_query(merged_params)

    uri.to_s
  end
end
