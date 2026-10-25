# frozen_string_literal: true

# VC › BPGUID Lookup: look a person up by callsign, search Salesforce Accounts
# (SOSL), and copy a chosen contact's BPGUID__c onto person.bpguid -- the link
# members are told to email the Volunteer Coordinators for.
#
# Nothing here answers 422: RequestLogger keeps a 422's parameters and page in
# request_log, and this page holds a person's address and phones plus other
# people's Salesforce contact details. search answers 200 with turbo streams.
# update redirects 303 on success -- the row button is a Turbo method link that
# sends a real PATCH, and fetch follows a 302 by repeating the PATCH -- and
# answers a refusal at 200 with a turbo stream, so the results stay on screen.
class Vc::BpguidController < ApplicationController
  include PersonLookupConcern # carries no authorize_role, so the gate below stands

  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to link Burner Profiles."
  # D10: the training server's database is a redacted copy, but a build that
  # skipped the redaction, or credentials typed back in there, would reach the
  # live org. update needs no guard: only a search mints a link.
  before_action -> { prevent_if_ghd_server("Salesforce searches") }, only: :search
  # search runs with or without a person; only one shown can be linked.
  before_action :set_person, except: :index, if: -> { params.key?(:person_id) }

  def index
    @callsign = params[:callsign].to_s.squish
    return if @callsign.blank?

    person = find_by_callsign(@callsign)
    return redirect_to vc_bpguid_person_path(person) if person

    flash.now[:error] = "No account has the callsign #{@callsign}. Check the spelling, then look it up again."
  end

  # One template for both: the two forms are always on the page.
  def show = render(:index)

  def search
    # last_name_or_email: the :email entry in filter_parameters masks it by partial match.
    search = SalesforceContactSearch.new(params.expect(:last_name_or_email).squish, person: @person).run

    render turbo_stream: [
      turbo_stream.update("vc-bpguid-results", partial: "results", locals: { search:, person: @person }),
      # turbo_stream.update marks a plain String html_safe; escape the sentence first.
      turbo_stream.update("live-region", ERB::Util.html_escape(search.summary))
    ]
  end

  def update
    # Nothing typed reaches person.bpguid: the value comes from the row's signed
    # link, minted when a search rendered the row (link_token, filtered in logs).
    link = SalesforceContactSearch.verified_link(params.expect(:link_token))
    unless link && link["person_id"] == @person.id
      return refuse("This result is out of date. Search again, then choose the contact.")
    end

    bpguid = link["bpguid"].to_s
    if @person.bpguid.to_s != link["was"] # D8: another tab or VC linked since the search
      now = @person.bpguid.present? ? "it is now #{@person.bpguid}" : "it was cleared"
      refuse("#{@person.callsign}'s BPGUID changed since this search (#{now}). Search again before linking.")
    elsif bpguid.length > 64 # person.bpguid is varchar(64)
      refuse("That BPGUID is longer than the 64 characters the Clubhouse can store.")
    elsif (holder = Person.where(bpguid:).where.not(id: @person.id).pick(:callsign)) # D3, case-insensitive by collation
      refuse("#{bpguid} is already linked to #{holder}. " \
             "Ask an Admin to check whether the two accounts are the same person.")
    else
      @person.audit_reason = "BPGUID linked on VC › BPGUID Lookup"
      # update_attribute skips validation -- a legacy record failing an unrelated
      # check (blank street1, an old phone) still links -- and skips the E.164
      # phone rewrite, but still writes the person-update audit row.
      @person.update_attribute(:bpguid, bpguid)
      redirect_to vc_bpguid_person_path(@person), status: :see_other,
                                                  success: "#{@person.callsign}'s BPGUID is now #{bpguid}."
    end
  end

  private

  def person_not_found_path = vc_bpguid_path

  # D8: a refusal answers in place -- an error callout above the table, which
  # stays -- never a redirect and a toast that hides itself.
  def refuse(message)
    render turbo_stream: turbo_stream.update("vc-bpguid-notice", partial: "link_refused", locals: { message: })
  end

  # D12: the exact callsign first (unique index, case-insensitive collation), then
  # the normalized match, which ignores spacing and punctuation but is not unique.
  # Never Person.by_callsign: it calls an undefined method.
  def find_by_callsign(callsign)
    Person.find_by(callsign:) ||
      (Person.retrieve_by_callsign(callsign) if WordUtils.normalize_word(callsign).present?)
  end
end
