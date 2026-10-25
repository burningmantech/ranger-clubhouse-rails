# frozen_string_literal: true

# The year's handheld radio inventory (Ember reports/radio-assets port). Two
# views of one list: the full roster, and the same radios collapsed into the
# contiguous barcode blocks the cage issues them in.
class AssetManagement::RadioAssetsController < ApplicationController
  include AssetYearScopeConcern
  include CsvExportConcern

  layout "asset_management"

  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # The summary is a view of the same filtered list rather than a second page,
  # so it rides on a param and is part of the view's identity: every link on the
  # page carries it. Upstream's checkbox lost the summary on any reload, and
  # would lose it here on a year change or an Apply Filters too.
  SUMMARY_VIEW = "summary"

  # Radios are the one asset type whose perm_assign reads as event-vs-shift
  # rather than permanent-vs-temporary (see asset_duration_label). Named in
  # words rather than passed as the underlying boolean: "?duration=false"
  # arrives as the string "false", which is truthy.
  DURATION_EVENT = "event"
  DURATION_SHIFT = "shift"
  DURATIONS = [DURATION_EVENT, DURATION_SHIFT].freeze

  # Descriptions that collide with a filter sentinel and so can never be offered
  # as a choice -- see selectable_descriptions.
  RESERVED_DESCRIPTIONS = [ALL_FILTER, Asset::BLANK_FILTER_VALUE].freeze

  PAGE_SIZE = 100

  # Upstream: ADMIN or EDIT_ASSETS (AssetPolicy::before) or EVENT_MANAGEMENT
  # (AssetPolicy::index), named here exactly, as on the sibling reports.
  #
  # The Ember client is stricter than its own API here -- it gates the whole
  # Reports menu on admin-or-manage, so an EDIT_ASSETS holder could call the
  # endpoint but never reach the page. The API is the authority, and it is what
  # the two sibling reports already follow.
  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  def index
    load_report

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: csv_filename) }
    end
  end

  private

  def load_report
    @available_years = radio_years
    @year = resolve_selected_year(@available_years, params[:year])
    # The sidebar carries the year the reader was on, and this page's year list
    # is a strict subset of its three siblings' -- they browse every year holding
    # any asset. Arriving from a year that holds gear but no radios silently
    # lands on a different year, so the page has to say so rather than let the
    # shell and the table disagree.
    @requested_year = requested_other_year
    @radios = @year ? Asset.find_for_query(year: @year, type: Asset::TYPE_RADIO) : []

    # One query, then narrow in memory: a year holds a few hundred radios, and
    # the Description select needs the unfiltered set to list its options.
    @summary_view = params[:view] == SUMMARY_VIEW
    # Assigned before @filter_params rather than lazily: the Description select
    # needs the list whether or not a description was requested, and
    # requested_description returns early without asking for it when the param
    # is absent.
    @selectable_descriptions = selectable_descriptions
    @filter_params = { duration: requested_duration, description: requested_description,
                       barcode: requested_barcode }
    @filtered_radios = filtered_radios
    @ranges = RadioAssetRanges.build(@filtered_radios)
    @view_params = view_params
    @index_params = @view_params.merge(active_filters)

    load_stats
    paginate_rows
  end

  # Years come from the radios themselves: this page has nothing to say about a
  # year that holds only gear. (2020 and 2021 have no asset rows at all, so the
  # pandemic skips itself -- upstream hardcodes a 2010 floor and a pandemic
  # skip, and hides 2009's 275 radios doing it.)
  def radio_years
    Asset.where(type: Asset::TYPE_RADIO).distinct.order(year: :desc).pluck(:year)
  end

  # The year that was asked for and could not be shown, when it is a real
  # inventory year rather than a typo -- a garbled param already falls back
  # silently and has nothing to explain.
  def requested_other_year
    requested = params[:year].to_s.presence&.to_i
    return nil if requested.nil? || requested == @year || @available_years.include?(requested)

    Asset.exists?(year: requested) ? requested : nil
  end

  # AssetYearScopeConcern's default_year (the newest year offered) is right
  # here, with none of the "year that saw activity" refinement the two checkout
  # reports need: on an inventory page the inventory is the activity, so the
  # newest year holding radios always has rows to show.

  # Which of the two tables is on screen is part of the view's identity, exactly
  # like the year: a chip, a pager link or the CSV button that dropped it would
  # quietly return the reader to the roster.
  def view_params
    { year: @year, view: (SUMMARY_VIEW if @summary_view) }.compact_blank
  end

  def active_filters
    UiComponents::FilterBarHelper.active_filters(@filter_params)
  end

  # Two values, both always meaningful, so unlike the sibling reports there is
  # nothing to check against the year's data: anything unrecognized reads as
  # "all".
  def requested_duration
    duration = params[:duration].presence
    DURATIONS.include?(duration) ? duration : ALL_FILTER
  end

  # A description the year does not hold would empty the table while its own
  # chip promised rows, so it too reads as "all". blank? first: with no filter
  # applied the param is nil, and the year's NULL-described radios would
  # otherwise match it and narrow the default page to just those.
  def requested_description
    description = params[:description].presence
    return ALL_FILTER if description.blank?

    @selectable_descriptions.include?(description) ? description : ALL_FILTER
  end

  # The descriptions a reader can actually be offered, narrowed by whatever
  # duration is already applied: of 2024's 45 descriptions, 37 belong only to
  # event radios and 5 only to shift radios, so an unnarrowed list invites
  # Shift + an event-only block and delivers nothing. A select navigates, so it
  # has to promise the roster the choice delivers.
  #
  # Two values are withheld because they cannot survive the round trip: a
  # description of "all" is indistinguishable from the filter-off sentinel, and
  # one of "Blank" from the no-description sentinel. Offering either draws a
  # second option with a duplicate value and a choice that quietly does nothing.
  # BLANK_FILTER_VALUE is offered only when a radio really has no description --
  # NULL is a real value here, 2024 holds two and 2023 ten.
  def selectable_descriptions(radios = duration_scoped_radios)
    values = radios.filter_map { |radio| radio.description.presence }
                   .reject { |value| RESERVED_DESCRIPTIONS.include?(value) }
    values << Asset::BLANK_FILTER_VALUE if radios.any? { |radio| radio.description.blank? }

    values.uniq.sort
  end

  # The duration filter narrows the description choices, but not the reverse:
  # duration is a closed two-value vocabulary that is always offered whole.
  def duration_scoped_radios
    duration = requested_duration
    return @radios if duration == ALL_FILTER

    @radios.select { |radio| radio.perm_assign? == (duration == DURATION_EVENT) }
  end

  # Free text, and deliberately not validated against the roster: an unmatched
  # barcode has to reach the empty state saying so, which is the answer the
  # reader came for. to_s guards an Array or Hash param.
  def requested_barcode
    params[:barcode].to_s.strip.presence || ALL_FILTER
  end

  def filtered_radios
    duration = @filter_params[:duration]
    description = @filter_params[:description]
    barcode = @filter_params[:barcode]
    radios = @radios

    unless duration == ALL_FILTER
      radios = radios.select { |radio| radio.perm_assign? == (duration == DURATION_EVENT) }
    end
    radios = radios.select { |radio| matches_description?(radio, description) } unless
      description == ALL_FILTER
    # Substring, case-insensitive: the reader is hunting one barcode and often
    # has only the tail of it off a scuffed label.
    radios = radios.select { |radio| radio.barcode.to_s.downcase.include?(barcode.downcase) } unless
      barcode == ALL_FILTER

    radios
  end

  # BLANK_FILTER_VALUE means "no description", exactly as Asset's own
  # apply_nullable_filter reads it. Comparing the folded key instead would make
  # this page's `description` mean something subtly different from the records
  # page's -- and that param now rides between the two on the Back link.
  def matches_description?(radio, description)
    return radio.description.blank? if description == Asset::BLANK_FILTER_VALUE

    radio.description == description
  end

  # The stat boxes describe what is on screen rather than the year: with Shift
  # chosen, a headline counting the year's event radios would contradict every
  # row and every badge beneath it. How much was narrowed away is the filter
  # bar's count line to state.
  def load_stats
    @radio_count = @filtered_radios.size
    @event_count = @filtered_radios.count(&:perm_assign?)
    @shift_count = @radio_count - @event_count
    @range_count = @ranges.size
  end

  # Whichever table is on screen is the one that pages. The summary is short in
  # practice -- 50 ranges against 571 radios in 2024 -- but a year whose
  # barcodes never run consecutively collapses to nothing at all, so it gets the
  # same treatment rather than a promise about the data.
  #
  # Pagy has no array backend in v43 and the barcode order comes from
  # Asset.natural_sort in Ruby, so the page is sliced here rather than in SQL.
  def paginate_rows
    rows = @summary_view ? @ranges : @filtered_radios
    @total_pages = [(rows.size / PAGE_SIZE.to_f).ceil, 1].max
    # clamp, not a bare to_i: params[:page] can arrive as an Array or a Hash,
    # which to_s renders into something to_i reads as 0.
    @page = (params[:page].to_s.presence&.to_i || 1).clamp(1, @total_pages)
    @page_rows = rows[(@page - 1) * PAGE_SIZE, PAGE_SIZE] || []
  end

  # The filters and the view travel in the filename: exporting the roster and
  # then the summary otherwise hands the reader two files with one name.
  def csv_filename
    duration = @filter_params[:duration]
    description = @filter_params[:description]

    parts = [@year,
             (duration unless duration == ALL_FILTER),
             (description_slug(description) unless description == ALL_FILTER),
             (SUMMARY_VIEW if @summary_view),
             # Not "radio-assets.csv": the Asset Inventory type page exports
             # "#{year}-#{type}-assets.csv", which for type=radio is exactly
             # "#{year}-radio-assets.csv" -- a different report with eleven
             # columns under the same name.
             "radio-assets-report.csv"]

    parts.compact.join("-")
  end

  # Labelled, unlike the two fixed-vocabulary parts around it: descriptions are
  # free text, so an unlabelled one can land in the slot a sibling part occupies
  # and give ?description=Event the same filename as ?duration=event. Also
  # parameterized -- the real ones read "Event | EXP 9/2 12:00", and those
  # slashes are path separators.
  #
  # parameterize is lossy in both directions: "Other" and "———" both reduce to
  # the same token once the empty result is defaulted, and "other" and "OTHER"
  # collide outright. A short digest of the exact text rides along so two
  # different filtered exports can never share a filename.
  def description_slug(description)
    slug = description.parameterize.presence || "other"

    "description-#{slug}-#{Digest::MD5.hexdigest(description)[0, 6]}"
  end

  # The whole filtered list, not the visible page -- an export stopping at 100
  # rows would silently under-report the year. Upstream has no export at all;
  # the columns are the ones on screen.
  def csv_rows
    @summary_view ? summary_csv_rows : roster_csv_rows
  end

  def roster_csv_rows
    rows = [["Barcode", "Description", "Duration"]]

    @filtered_radios.each do |radio|
      rows << [radio.barcode, radio.description, helpers.asset_duration_label(radio)]
    end

    rows
  end

  def summary_csv_rows
    rows = [["Barcode Range", "Count", "Description", "Duration"]]

    @ranges.each do |range|
      rows << [range.label, range.count, range.description,
               helpers.asset_duration_label(range.exemplar)]
    end

    rows
  end
end
