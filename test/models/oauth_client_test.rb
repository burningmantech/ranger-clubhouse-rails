# frozen_string_literal: true

require "test_helper"

class OauthClientTest < ActiveSupport::TestCase
  setup do
    @client = oauth_client(:moodle)
  end

  # ---------------------------------------------------------------- secret

  test "a new client is given a secret it was not asked for" do
    client = OauthClient.create!(client_id: "brand-new", description: "A new website",
                                 redirect_uri: "https://new.example.org/callback")

    assert_equal OauthClient::SECRET_LENGTH, client.secret.length
    assert_match(/\A[a-zA-Z0-9]+\z/, client.secret)
  end

  test "a secret sent along with a new client is thrown away" do
    client = OauthClient.create!(client_id: "brand-new", description: "A new website",
                                 redirect_uri: "https://new.example.org/callback",
                                 secret: "a-secret-somebody-else-chose")

    assert_not_equal "a-secret-somebody-else-chose", client.secret
    assert_equal OauthClient::SECRET_LENGTH, client.secret.length
  end

  test "generating a secret replaces the one the client had" do
    was = @client.secret

    @client.generate_secret

    assert_not_equal was, @client.secret
    assert_equal OauthClient::SECRET_LENGTH, @client.secret.length
  end

  test "a saved client keeps the secret it was given" do
    was = @client.secret

    @client.update!(description: "A new description")

    assert_equal was, @client.reload.secret
  end

  # ----------------------------------------------------------- validations

  test "a new client needs an id and a description" do
    client = OauthClient.new

    assert_not client.valid?
    assert_predicate client.errors[:client_id], :any?
    assert_predicate client.errors[:description], :any?
    # Not the secret: a new client is given one before its rules are checked,
    # so the secret rule only ever has something to say on an existing client.
    assert_empty client.errors[:secret]
    # Not the return address either -- the model stopped constraining it. See
    # the note on the accepts_redirect_uri? test below for where the guard is.
    assert_empty client.errors[:redirect_uri]
  end

  test "text longer than the column is refused rather than raising" do
    too_long = "x" * (OauthClient::TEXT_COLUMN_LIMIT + 1)

    # No :redirect_uri -- it has no length rule any more, so the column is what
    # would refuse an over-long one, by raising rather than by validating.
    [:client_id, :description, :secret].each do |field|
      # A fresh copy each time, read back rather than taken from the fixture
      # accessor, which hands out the same object every call -- reusing it
      # carries the last field's error over and the check stops proving
      # anything about this one. Saved rather than new, because a new client is
      # handed a secret of the right length before its rules are ever checked.
      client = OauthClient.find(@client.id)
      client[field] = too_long

      assert_not client.valid?, "#{field} must be capped"
      assert_predicate client.errors[field], :any?
    end
  end

  test "a blank secret on an existing client is refused" do
    @client.secret = ""

    assert_not @client.valid?
    assert_predicate @client.errors[:secret], :any?
  end

  # The model used to refuse a return address that was not a full web address
  # without a fragment. That validation is commented out and the admin form no
  # longer offers the field, so nothing checks the value on the way in -- this
  # pins that, so the day it comes back a failure here says so.
  #
  # It is not the security boundary and never was. accepts_redirect_uri? is,
  # and it is asked twice: sso_controller#authorize before a code is handed
  # out, and sso/api_controller#token before one is redeemed.
  test "the model no longer refuses any shape of return address" do
    ["learn.example.org/callback", "ftp://learn.example.org/", "https://learn.example.org/cb#top",
     "https://learn.example.org/a b", ""].each do |any|
      @client.redirect_uri = any
      assert @client.valid?, "#{any.inspect} is no longer the model's business"
    end
  end

  # This is the whole guard now that the validation is gone: an exact match
  # against what is stored.
  test "a code may go only to the recorded address, written the same way" do
    assert @client.accepts_redirect_uri?(@client.redirect_uri)
    assert_not @client.accepts_redirect_uri?("#{@client.redirect_uri}/")
    assert_not @client.accepts_redirect_uri?(nil)
    assert_not @client.accepts_redirect_uri?([@client.redirect_uri])
  end

  test "a client with nothing recorded accepts any address" do
    @client.redirect_uri = ""
    assert @client.accepts_redirect_uri?("")
    assert @client.accepts_redirect_uri?(nil)
    assert @client.accepts_redirect_uri?("https://anywhere.example.org/cb")
  end

  test "two clients cannot share an id" do
    client = OauthClient.new(client_id: @client.client_id, description: "Another website")

    assert_not client.valid?
    assert_predicate client.errors[:client_id], :any?
  end

  # ------------------------------------------------------------- normalizing

  test "space around a value is taken off before it is stored" do
    client = OauthClient.new(client_id: "  spaced-out  ", description: "  A website  ",
                             secret: "  a-secret-with-space  ",
                             redirect_uri: "  https://learn.example.org/cb  ")

    assert_equal "spaced-out", client.client_id
    assert_equal "A website", client.description
    assert_equal "a-secret-with-space", client.secret
    assert_equal "https://learn.example.org/cb", client.redirect_uri
  end

  # The wide space a copied value brings with it reads as an ordinary space to
  # a person, and as a different character to the website being signed in to.
  test "a wide space around a value is taken off too" do
    client = OauthClient.new(client_id: "\u00A0ranger-moodle\u00A0", description: "A website")

    assert_equal "ranger-moodle", client.client_id
  end

  # --------------------------------------------------------------- reading

  # Read the rows, not the column: plucking one column can be answered from
  # the index, which hands back sorted rows whether or not the sort was asked
  # for -- so a plucked list passes even with no ordering at all.
  test "clients are listed by id" do
    assert_equal ["ranger-hq-osticket", "ranger-moodle"],
                 OauthClient.ordered.to_a.map(&:client_id)
  end

  # -------------------------------------------------------------- deleting

  test "deleting a client takes its sign-in codes with it" do
    OauthCode.create!(oauth_client: @client, person_id: person(:active_ranger).id,
                      code: "a-sign-in-code", scope: "openid", created_at: Current.time)

    assert_difference "OauthCode.count", -1 do
      @client.destroy
    end
  end

  # ------------------------------------------------------------- audit log

  test "the secret never reaches the action log" do
    ActionLog.delete_all

    client = OauthClient.create!(client_id: "brand-new", description: "A new website",
                                 redirect_uri: "https://new.example.org/callback")

    entry = ActionLog.where(event: "oauth-client-create").last
    assert_not_nil entry
    # Name the column outright. Reading the list the guard is built from would
    # make this pass by doing nothing the moment that list went empty.
    assert_includes OauthClient.audit_exclude, "secret"
    assert_not entry.data.key?("secret"), "the secret must stay out of the action log"
    assert_equal client.client_id, entry.data["client_id"]
  end

  # The excluded value is dropped from the entry rather than masked, so a save
  # that touches nothing else would have an empty payload and write no row at
  # all. What keeps a rotation on the record is the timestamp that changes
  # alongside it. Asserting that here on purpose: if the timestamp ever stops
  # being recorded, rotations go silently unlogged, and this is where it shows.
  test "changing only the secret is still recorded" do
    ActionLog.delete_all

    @client.generate_secret
    @client.save!

    entry = ActionLog.where(event: "oauth-client-update").last
    assert_not_nil entry, "rotating a secret must leave a trace"
    assert_not entry.data.key?("secret")
    assert entry.data.key?("updated_at"), "the timestamp is what keeps the entry from being empty"
  end
end
