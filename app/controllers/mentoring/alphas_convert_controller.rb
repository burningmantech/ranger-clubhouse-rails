# frozen_string_literal: true

# Convert Alphas: the last step of the mentoring season (upstream Ember
# mentor/convert-alphas, backed by MentorController::verdicts and
# ::convertAlphas). The Alphas whose mentors have recorded a verdict, in two
# sections -- passed Alphas minted into active Rangers, bonked and self-bonked
# Alphas moved to bonked status.
#
# The two outcomes are kept as two forms with two buttons, matching upstream:
# both are irreversible from here, and one shared button would let a single
# click mint and bonk at the same time. Each form names its own outcome, and
# AlphaConversion refuses a person whose verdict points the other way.
class Mentoring::AlphasConvertController < ApplicationController
  layout "mentoring"

  before_action :setup_year

  # Upstream Gate isMentor.
  authorize_role [Role::ADMIN, Role::MENTOR],
                 message: "Admin or Mentor role required to convert Alphas."

  def index
    @converted = []
    @skipped_count = 0
    @target = nil
    load_roster
  end

  # Renders the roster again instead of redirecting, like the sibling Convert
  # Prospectives page: a GET cannot re-derive who was just converted -- they are
  # not Alphas any more, and so off the roster the page is built from -- and
  # Turbo drops a 200 form response. The house 422 results pattern, with the
  # just-converted people held on the page one last time.
  def convert
    @target = params[:target].to_s

    unless AlphaConversion::VERDICTS_FOR_TARGET.key?(@target)
      return redirect_to mentoring_alphas_convert_path,
                         alert: "Use one of this page's own buttons to convert Alphas."
    end

    # Deduplicated because the skipped count is derived by subtraction: the same
    # id sent twice converts one person and would otherwise be reported as one
    # person who could not be converted.
    ids = IdList.parse(params.permit(person_ids: [])[:person_ids])

    if ids.empty?
      return redirect_to mentoring_alphas_convert_path, alert: nothing_checked_alert
    end

    @converted = AlphaConversion.convert(ids, target: @target, year: @year)
    @skipped_count = ids.size - @converted.size
    load_roster

    render :index, status: :unprocessable_entity
  end

  private

  # Pinned, not read from params: the roster is who holds Alpha status right
  # now, so honouring ?year= would offer today's Alphas against a past year's
  # verdicts. Upstream's endpoint takes no year either. Matches the other
  # current-standing Mentoring pages.
  def setup_year
    @year = Current.year
  end

  # @converted is already set by the time this runs, so the just-converted
  # people are both held on the page and left out of the two counts, which
  # describe who is still waiting to be converted.
  def load_roster
    @converted_ids = @converted.map(&:id).to_set
    @rows = AlphaConversion.roster(@year, keep_ids: @converted_ids.to_a)

    @mint_rows = @rows.select(&:mint?)
    @bonk_rows = @rows.select(&:bonk?)

    remaining = @rows.reject { |row| @converted_ids.include?(row.person.id) }
    @mint_count = remaining.count(&:mint?)
    @bonk_count = remaining.count(&:bonk?)
  end

  def nothing_checked_alert
    if @target == Person::ACTIVE
      "Check at least one Shiny Penny candidate to mint."
    else
      "Check at least one Alpha to bonk."
    end
  end
end
