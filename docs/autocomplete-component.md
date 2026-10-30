# Autocomplete Component

## 1. Overview

The autocomplete component provides a reusable, accessible search interface for form fields and global search functionality. It supports:

- Real-time search with server-side results
- Grouped and flat result layouts
- Dynamic filter UI with single-select mode (v1)
- Backend-rendered HTML for rich result items
- Metadata writeback to hidden form fields
- Full keyboard navigation (WCAG 2.1 Level AA compliant)
- Auto-positioning (flips above when insufficient space below)
- Request cancellation and stale response handling
- Reduced-motion compliance

The component is built with Stimulus.js and integrates seamlessly with Rails form helpers.

## 2. Request Contract

**Endpoint:** `GET /autocomplete/search` (JSON)

### Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `q` | string | Yes | - | Search query string |
| `mode` | string | Yes | - | Search mode (e.g., "person_manage", "hq") |
| `limit` | integer | No | 5 | Maximum number of results to return |
| `filters` | string | No | null | JSON-encoded filter object with active filter values (v1: single-select only, e.g. `{"status_group":"active_current"}`) |

### Example Request

```
GET /autocomplete/search?q=boy&mode=person_manage&limit=10&filters=%7B%22status_group%22%3A%22active_current%22%7D
```

### Request Cancellation

The Stimulus controller automatically cancels in-flight requests when a new search is initiated, preventing race conditions and outdated results from appearing.

### Failures

Signed out, the endpoint answers `401`, not the sign-in redirect (`AutocompleteController#request_authentication`).
A failed search dispatches `autocomplete.error` with `detail: { error, kind }`. The `kind` is:

- `offline`: no answer at all, or one cut off while its body was read, because there's no
  connection or the server is unreachable (a `TypeError` from `fetch` or the body read)
- `expired`: a `401`
- `failed`: anything else, including an answer that isn't JSON

The event is cancelable. Without a listener, the component shows its own one-line `.ac-error`
in the list. A host that says it itself cancels the event, and the list just goes: the search
bar does this, showing one of its `application/_dialog_status` callouts. An aborted or
superseded search fires no `autocomplete.error`.

`refetch()` runs the last search again, filter chips and all; the search bar's Try Again calls
it through a Stimulus outlet. In the inline variant, a search still out after 10 seconds says so
in its own Searching row ("Still searching. Your connection may be slow.").

## 3. Response Contract

### Unified JSON Response Format

```json
{
  "request_id": "uuid-or-seq",
  "query": "boy",
  "mode": "person_manage",
  "empty_text": "No results found",
  "filters": [
    {
      "key": "status",
      "label": "Status",
      "multi": false,
      "options": [
        {
          "value": "active",
          "label": "Active/Current",
          "active": true,
          "count": 23
        },
        {
          "value": "inactive",
          "label": "Inactive",
          "active": false,
          "count": 4
        }
      ]
    }
  ],
  "groups": [
    {
      "key": "callsign",
      "title": "Callsign",
      "item_ids": ["i1", "i2"]
    },
    {
      "key": "name",
      "title": "Real Name",
      "item_ids": ["i3"]
    }
  ],
  "flat_item_ids": ["i1", "i2", "i3"],
  "items": [
    {
      "id": "i1",
      "value": "123",
      "label": "Happy Boy",
      "html": "<div class=\"autocomplete-item-content\">...</div>",
      "meta": {
        "id": 123,
        "status": "active",
        "callsign": "Happy Boy"
      }
    }
  ],
  "meta": {
    "result_count": 3,
    "search_time_ms": 42
  }
}
```

### Response Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `request_id` | string | No | Unique identifier for request tracking and stale detection |
| `query` | string | Yes | Echo of the search query |
| `mode` | string | Yes | Echo of the search mode |
| `empty_text` | string | No | Custom message when no results found (default: "No results found") |
| `filters` | array | No | Available filter groups with options and counts |
| `groups` | array | No | Group definitions for organized results (omit for flat layout) |
| `flat_item_ids` | array | Yes | Ordered list of all item IDs for keyboard navigation |
| `items` | array | Yes | Result items with HTML and metadata |
| `meta` | object | No | Additional metadata about the search |

### Item Structure

Each item in the `items` array must include:

- **`id`** (string, required): Unique identifier for the item
- **`value`** (string, required): Value to write to the form field on selection
- **`label`** (string, required): Plain text label for accessibility and fallback
- **`html`** (string, required): Backend-rendered HTML for the result display
- **`meta`** (object, optional): Additional metadata for writeback to hidden fields

### Filter Structure

Each filter in the `filters` array includes:

- **`key`** (string): Unique filter identifier
- **`label`** (string): Human-readable filter name
- **`multi`** (boolean): Whether multiple options can be selected (v1: always `false`)
- **`options`** (array): Available filter options with:
  - `value` (string): Option value
  - `label` (string): Display label
  - `active` (boolean): Whether this option is currently active
  - `count` (integer): Number of results with this filter value

### Group Structure

Each group in the `groups` array includes:

- **`key`** (string): Unique group identifier
- **`title`** (string): Display title for the group header; a blank title draws no header (the mailbox search's own row, above its People and Teams)
- **`item_ids`** (array): Ordered list of item IDs in this group

## 4. ARIA & Accessibility

The autocomplete component follows WCAG 2.1 Level AA standards with comprehensive ARIA support:

### Roles

- **Combobox wrapper**: `role="combobox"` on the outer container
- **Results container**: `role="listbox"` on the results dropdown
- **Result options**: `role="option"` on each selectable item
- **Group headers**: `role="presentation"` (decorative only, not selectable)

### ARIA Attributes

| Attribute | Element | Purpose |
|-----------|---------|---------|
| `aria-expanded` | Combobox wrapper | "true" when results shown, "false" when closed |
| `aria-controls` | Input field | References the results listbox ID |
| `aria-owns` | Input field | References the results listbox ID |
| `aria-activedescendant` | Input field | References the currently focused option ID |
| `aria-selected` | Option | "true" for the keyboard-selected option |
| `aria-disabled` | Option | "true" for disabled/unselectable items |
| `aria-describedby` | Input field | References help text or error message |

### Accessibility Features

- **Minimum 36px touch targets** (WCAG 2.5.8) for all interactive elements
- **Visible focus rings** (WCAG 2.4.7) with 2px brand-colored outline
- **Screen reader announcements** for result count changes using live regions
- **Clear error states** with error icons and color (not relying on color alone)
- **Keyboard-only operation** without requiring mouse interaction
- **Reduced motion support** via `prefers-reduced-motion` media query

### Live Region Announcements

The component announces search status changes to screen readers:

```html
<div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
  <!-- Dynamically updated by controller -->
</div>
```

Examples:
- "Searching..."
- "3 results found"
- "No results found"

## 5. Keyboard Map

| Key | Context | Action |
|-----|---------|--------|
| **ArrowDown** | Input focused, results open | Move to next option (wraps to first) |
| **ArrowUp** | Input focused, results open | Move to previous option (wraps to last) |
| **Enter** | Search in progress | Wait for the results; commit a sole result |
| **Enter** | Option selected | Commit selection and close results |
| **Enter** | No selection, 1 result | Auto-select the single result |
| **Enter** | Global search dialog, the option has no page to open | Commit nothing (see Global search dialog) |
| **Enter** | No selection, multiple results | No action |
| **Enter** | Free text (`free_text`), the first row or none highlighted, or a search in progress | Empty the list and leave the key to the form, which sends the text at once |
| **Escape** | Results open | Close results dropdown; the key goes no further |
| **Escape** | Results not up yet | Call off the search still to come and an Enter waiting for it; the key is left to the page (a dialog closes on it) |
| Any key | Kept by an input method (`keyCode` 229) | No action |
| **Tab** | Form field, option selected, no search in progress | Commit selection, close results, move focus to next field |
| **Tab** | Search in progress, no selection, free text, or the global search dialog | Commit nothing; focus moves as in the two rows below |
| **Tab** | Nothing committed, filter chips shown | Move focus to the first filter chip; results stay open |
| **Tab** | Nothing committed, no filter chips | Close results, move focus to next field |
| **Enter** / **Space** | Filter chip focused | Apply that filter and return focus to the input |
| **Ctrl+K** | Global (Windows/Linux) | Open global search bar modal |
| **Cmd+K** | Global (macOS) | Open global search bar modal |
| **Ctrl+Shift+K** | Global (Windows/Linux) | Open the navigation mega menu |
| **Cmd+Shift+K** | Global (macOS) | Open the navigation mega menu |

### Keyboard Behavior Details

- **Wrapping navigation**: Arrow keys wrap around (up from first goes to last, down from last goes to first)
- **Scroll into view**: Selected option automatically scrolls into view using `scrollIntoView({ block: "nearest" })`, smoothly unless the reader prefers reduced motion
- **Visual selection**: Selected option receives `aria-selected="true"` and visual styling class
- **Search in progress**: From the keystroke that changes the text until the results for that text are shown or the list is emptied. It covers the debounce before the request starts, and text too short to search. A response for earlier text is discarded, and its failure shows no error
- **Typing over a chosen value**: In a form field the chosen value (the hidden target) is cleared by the keystroke itself, not after the debounce, so the form never submits the previous value under new text. Fields filled by metadata writeback are not cleared
- **Enter key handling**: If search is in progress when Enter is pressed, waits for results and auto-selects if only one result, ignoring any row still highlighted from the previous query. An Enter pressed on text too short to search is not kept. An Enter still waiting is forgotten on a dismissal (next), or when the text drops below the minimum length
- **Dismissal ends the search**: Escape, focus leaving the component, a result being chosen and the controller disconnecting drop the search in flight, call off the one still in its debounce, and forget an Enter waiting for either. No search follows until the text changes again
- **Input methods**: A keydown reported with `keyCode` 229 is a key the input method kept for itself, such as the Enter that confirms a composition or the arrows that pick a candidate, and is ignored. The test is `keyCode`, not `isComposing`: Safari reports that Enter with `isComposing` false, and a phone keyboard composes every word as it is typed, so its plain Enter (13) has to work mid-word
- **Tab key**: In a form field (a hidden value field, or submit-on-select), commits the selection if an option is selected and no search is in progress. In the global search dialog Tab commits nothing, whatever is highlighted: it only moves the focus, which keeps the filter chips reachable while an option is highlighted, as a lone result is on arrival
- **Click on the results that hits no option**: A click on the filter bar's background, a group header or a message hands focus back to the input
- **Focus leaving the component**: The results are cleared, as Escape clears them, when focus moves anywhere outside the input and its results, and a search still in flight is dropped. Switching windows or tabs does not count, because focus has not moved. Nothing is committed unless `select_on_blur` is set, and then only the highlighted option or a sole result, and never while a search is in progress, when those rows belong to the previous text
- **Global search dialog**: Does not set `select_on_blur`. A result opens only on Enter or a click, as in Clubhouse 2. A result with no page to open (a fleet or team vehicle has no owner) is not committed by Enter or a click, nor by an Enter that waited for its search: the dialog has no field for a value to go into. The text typed and the results stay as they are, that option is highlighted and focus stays in the input

## 6. Placement Rules

### Default Behavior

- **Position**: Dropdown appears directly below the input field
- **Width**: Matches input width minimum, expands if content requires more space
- **Max height**: 20em (approximately 10-12 results) with vertical scroll
- **Margin**: 0.25rem (4px) gap between input and dropdown

### Auto-Flip

The component automatically flips above the input when:

1. Insufficient space below input (less than dropdown height)
2. More space available above input
3. Window is scrolled near bottom

Flip detection runs on:
- Initial open
- Window resize
- Window scroll

### Z-Index Layering

- **Inline autocomplete**: `z-index: 9500` (high but below modals)
- **Modal search bar**: Uses modal's z-index layer (typically `z-index: 10000+`)
- **Fixed positioning**: Used for global search bar to ensure visibility

### CSS Classes

```css
.autocomplete-results-box-dropdown {
  position: absolute;
  z-index: 9500;
  box-shadow: 0 1px 5px 0 rgb(50 50 50 / 50%);
  max-height: 20em;
  overflow-y: auto;
  background-color: #fafafa;
  margin-top: 0.25rem;
  border: 2px solid #ececec;
  border-radius: 5px;
}

/* Flipped above input */
.autocomplete-results-box-dropdown.flipped {
  margin-top: 0;
  margin-bottom: 0.25rem;
}
```

## 7. Filter Rules

### Default Behavior

- **Single-select**: Only one option per filter group can be active at a time
- **Active indication**: Active filters shown with visual styling (e.g., checkmark icon)
- **Filter chips**: Active filters displayed as removable chips/pills below search input
- **Count updates**: Server returns updated counts with each response

### Future Extension: Multi-Select Filters (not in v1)

v1 supports single-select filters only (`multi: false`). Multi-select support may be added in a future version. Until then:
- Only one option per filter group can be active at a time
- Clicking a new option deactivates the previous one
- The `filters` request parameter accepts only flat key-value pairs (e.g., `{"status_group":"active_current"}`)

### Filter UI Elements

```html
<div class="autocomplete-filters">
  <!-- Active filter chips -->
  <div class="filter-chips">
    <button type="button" class="filter-chip" data-filter-key="status" data-filter-value="active">
      Active/Current
      <span class="remove-icon">×</span>
    </button>
  </div>

  <!-- Available filters -->
  <div class="filter-group" data-filter-key="status">
    <label class="filter-group-label">Status</label>
    <div class="filter-options">
      <button type="button" class="filter-option active" data-value="active">
        Active/Current (23)
      </button>
      <button type="button" class="filter-option" data-value="inactive">
        Inactive (4)
      </button>
    </div>
  </div>
</div>
```

### Filter Request Flow

1. User clicks filter option → component updates active filters
2. Component sends new search request with updated `filters` parameter
3. Server returns updated results and filter counts
4. Component updates UI with new results and counts

## 8. Metadata Writeback

Metadata writeback allows automatic population of hidden form fields based on the selected item's metadata.

### Configuration

The caller provides a mapping hash when initializing the autocomplete:

```ruby
autocomplete_field(
  :person_id,
  mode: "person_manage",
  metadata_mapping: {
    "id" => "person_id_hidden",
    "status" => "person_status_hidden",
    "callsign" => "person_callsign_hidden"
  }
)
```

### Behavior

1. **Selection**: User selects an item from results
2. **Read metadata**: Controller reads `item.meta` object from JSON
3. **Match fields**: For each key in the mapping, looks for matching field by ID
4. **Write values**: Writes `meta[key]` to the corresponding hidden field
5. **Dispatch events**: Triggers `input` and `change` events on each updated field

### Example Flow

Given this selection:

```json
{
  "id": "i123",
  "value": "123",
  "label": "Happy Boy",
  "meta": {
    "id": 123,
    "status": "active",
    "callsign": "Happy Boy",
    "years": 5
  }
}
```

And this mapping:

```json
{
  "id": "person_id_hidden",
  "status": "person_status_hidden"
}
```

Result:
- Field `#person_id_hidden` gets value `123`
- Field `#person_status_hidden` gets value `"active"`
- Field `#person_years_hidden` is **not updated** (not in mapping)
- Both updated fields dispatch `input` and `change` events

### Event Handling

Other Stimulus controllers can listen for changes:

```javascript
// Listen for metadata changes
document.getElementById('person_status_hidden').addEventListener('change', (event) => {
  console.log('Status updated:', event.target.value);
});
```

### Use Cases

- **Dependent field population**: Auto-fill related fields based on selection
- **Validation**: Update form state based on selected item properties
- **UI updates**: Trigger display changes based on metadata (e.g., show/hide sections)
- **Analytics**: Track selection metadata for reporting

## 9. Stimulus Controller Values

The autocomplete Stimulus controller accepts the following data values:

### Core Values

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `url` | String | required | API endpoint URL for fetching results |
| `mode` | String | required | Search mode identifier (e.g., "person_manage") |
| `minLength` | Number | 2 | Minimum query length before searching |
| `delay` | Number | 300 | Debounce delay in milliseconds |
| `queryParam` | String | "q" | Query parameter name for the search string |
| `limit` | Number | 5 | Maximum number of results to request |
| `submitOnSelect` | Boolean | false | Auto-submit form after selection |
| `freeText` | Boolean | false | The text is itself a choice (the mailbox search, `free_text: true` on `shared/_autocomplete`): the first row stands for it and arrives highlighted, Enter sends the form with the text without waiting for the list unless the reader picked a row below the first, and Tab takes no row. A held Enter (`pendingEnter`) commits only a sole result, so without this a person among the suggestions swallowed the Enter |
| `formField` | Boolean | false | A form field with no hidden target: a selection fills the input and dispatches `autocomplete.change` (the callsign chips field, `form_field: true` on `shared/_autocomplete`) |

### Optional Values

| Value | Type | Default | Description |
|-------|------|---------|-------------|
| `metadataMapping` | Object | null | JSON object mapping metadata keys to field IDs |
| `placeholder` | String | "Search..." | Input placeholder text |
| `emptyText` | String | "No results found" | Message when no results |
| `renderBelow` | Boolean | true | Whether to render dropdown below input |
| `autoFlip` | Boolean | true | Auto-flip dropdown when insufficient space |

### Example HTML

```html
<div
  data-controller="autocomplete"
  data-autocomplete-url-value="/autocomplete/search"
  data-autocomplete-mode-value="person_manage"
  data-autocomplete-min-length-value="2"
  data-autocomplete-delay-value="300"
  data-autocomplete-limit-value="10"
  data-autocomplete-metadata-mapping-value='{"id":"person_id","status":"person_status"}'
>
  <input
    type="search"
    data-autocomplete-target="input"
    placeholder="Search people..."
  />
  <input
    type="hidden"
    name="person_id"
    data-autocomplete-target="hidden"
  />
  <div
    data-autocomplete-target="results"
    role="listbox"
    hidden
  ></div>
</div>
```

### CSS Classes

The controller uses the following CSS class values (customizable):

| Class Value | Default | Purpose |
|-------------|---------|---------|
| `selected` | "autocomplete-option-selected" | Applied to keyboard-selected option |

Example:

```html
<div
  data-controller="autocomplete"
  data-autocomplete-selected-class="bg-base-200"
>
```

## 10. View Partial Usage

### Shared Partial

The `shared/_autocomplete.html.erb` partial provides the complete HTML structure:

```erb
<%# app/views/shared/_autocomplete.html.erb %>

<div
  class="autocomplete-wrapper <%= wrapper_class %>"
  data-controller="autocomplete"
  data-autocomplete-url-value="<%= url %>"
  data-autocomplete-mode-value="<%= mode %>"
  data-autocomplete-min-length-value="<%= min_length || 2 %>"
  data-autocomplete-delay-value="<%= delay || 300 %>"
  data-autocomplete-limit-value="<%= limit || 5 %>"
  <%= "data-autocomplete-metadata-mapping-value='#{metadata_mapping.to_json}'" if metadata_mapping %>
  <%= "data-autocomplete-submit-on-select-value='true'" if submit_on_select %>
  aria-expanded="false"
>
  <%= label_tag label_for, label_text, class: "form-label" if label_text %>

  <div class="autocomplete-input-wrapper">
    <%= text_field_tag(
      field_name,
      field_value,
      class: "form-control autocomplete-input",
      placeholder: placeholder || "Search...",
      autocomplete: "off",
      spellcheck: false,
      data: { autocomplete_target: "input" },
      aria: {
        autocomplete: "list",
        controls: "#{field_name}_results",
        owns: "#{field_name}_results"
      }
    ) %>

    <%= hidden_field_tag(
      hidden_field_name,
      hidden_field_value,
      data: { autocomplete_target: "hidden" }
    ) if hidden_field_name %>
  </div>

  <div
    id="<%= field_name %>_results"
    class="autocomplete-results-box autocomplete-results-box-dropdown"
    data-autocomplete-target="results"
    role="listbox"
    hidden
  >
    <!-- Results populated by Stimulus controller -->
  </div>

  <%= content_tag(:p, help_text, class: "form-help-text") if help_text %>

  <!-- Screen reader live region -->
  <div role="status" aria-live="polite" aria-atomic="true" class="sr-only" data-autocomplete-target="announcer"></div>
</div>
```

### Form Builder Method

The `autocomplete_field` method extends `AppFormBuilder`:

```ruby
# Usage in a form
ui_form(@schedule, schedule_path(@schedule)) do |f|
  f.autocomplete_field(
    :person_id,
    label: "Select Person",
    mode: "person_manage",
    url: autocomplete_search_path,
    metadata_mapping: {
      "id" => "person_id",
      "status" => "person_status",
      "callsign" => "person_callsign"
    },
    limit: 10,
    help_text: "Start typing to search by callsign or name"
  )
end
```

### Method Signature

```ruby
def autocomplete_field(attribute, options = {})
  # Options:
  #   label: "Label text" (default: humanized attribute)
  #   mode: "search_mode" (required)
  #   url: "/path/to/endpoint" (required)
  #   metadata_mapping: { "meta_key" => "field_id" } (optional)
  #   min_length: 2 (default: 2)
  #   delay: 300 (default: 300)
  #   limit: 5 (default: 5)
  #   submit_on_select: false (default: false)
  #   placeholder: "Search..." (optional)
  #   help_text: "Help text" (optional)
  #   wrapper_class: "custom-class" (optional)
  #   width: "w-full" (optional)
  #   required: true (optional)
  #   hidden: false (optional)
end
```

### Standalone Usage (Outside Form Builder)

For views that need autocomplete without a form builder:

```erb
<%= render "shared/autocomplete",
  field_name: "person_search",
  label_text: "Find Person",
  label_for: "person_search",
  mode: "person_manage",
  url: autocomplete_search_path,
  min_length: 2,
  limit: 10,
  placeholder: "Type to search...",
  hidden_field_name: "person_id",
  metadata_mapping: { "id" => "person_id", "status" => "person_status" }
%>
```

### Required Partial Local Variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `field_name` | String | Yes | Input field name attribute |
| `mode` | String | Yes | Search mode identifier |
| `url` | String | Yes | Autocomplete endpoint URL |
| `label_for` | String | No | Label for attribute (if `label_text` present) |
| `label_text` | String | No | Label text to display |
| `placeholder` | String | No | Input placeholder |
| `hidden_field_name` | String | No | Name for hidden value field |
| `field_value` | String | No | Initial input value |
| `hidden_field_value` | String | No | Initial hidden value |
| `min_length` | Integer | No | Min query length (default: 2) |
| `delay` | Integer | No | Debounce ms (default: 300) |
| `limit` | Integer | No | Max results (default: 5) |
| `submit_on_select` | Boolean | No | Auto-submit form (default: false) |
| `metadata_mapping` | Hash | No | Metadata to field ID mapping |
| `help_text` | String | No | Help text below input |
| `wrapper_class` | String | No | Additional wrapper classes |

## Examples

### Example 1: Basic Person Search

```ruby
# In a view/form
f.autocomplete_field(
  :person_id,
  label: "Select Ranger",
  mode: "person_manage",
  url: autocomplete_search_path,
  required: true
)
```

### Example 2: With Metadata Writeback

```ruby
f.autocomplete_field(
  :person_id,
  label: "Select Ranger",
  mode: "person_manage",
  url: autocomplete_search_path,
  metadata_mapping: {
    "id" => "schedule_person_id",
    "status" => "schedule_person_status",
    "callsign" => "schedule_person_callsign"
  },
  help_text: "Start typing to search by callsign or name"
)
```

### Example 3: Auto-Submit Form on Selection

```ruby
# Useful for search/filter forms
ui_form(nil, search_path, method: :get) do |f|
  f.autocomplete_field(
    :person_id,
    label: "Quick Search",
    mode: "person_manage",
    url: autocomplete_search_path,
    submit_on_select: true
  )
end
```

## Related Documentation

- **UI Components Guide**: `/docs/UI-COMPONENTS.md` - Complete UI component reference
- **Design System**: `/docs/DESIGN-GUIDE.md` - Design tokens and patterns
- **Form Helper API**: `/docs/form_helper.md` - Form builder method signatures
- **Person Search Implementation**: `/app/lib/person_search.rb` - Person search adapter example

## Browser Support

- **Chrome/Edge**: 90+
- **Firefox**: 88+
- **Safari**: 14+
- **Mobile Safari**: 14+
- **Chrome Android**: 90+

## Performance Considerations

- **Debouncing**: 300ms default delay prevents excessive API calls
- **Request cancellation**: Aborts in-flight requests when new search starts
- **Stale response handling**: Ignores responses that arrive out of order
- **HTML caching**: Server can cache rendered HTML snippets
- **Result limits**: Default 5 results, adjustable per use case
- **Lazy rendering**: Results only rendered when dropdown opens

## Testing

### System Test Example

```ruby
# test/system/autocomplete_test.rb
test "autocomplete selection populates hidden field" do
  visit new_schedule_path

  # Type in autocomplete
  fill_in "Select Ranger", with: "Happy"

  # Wait for results
  assert_selector ".autocomplete-results-box [role='option']"

  # Press arrow down to select first result
  find("input[name='person_search']").send_keys(:arrow_down)

  # Press enter to select
  find("input[name='person_search']").send_keys(:enter)

  # Verify hidden field populated
  assert_equal "123", find("input[name='person_id']", visible: false).value
end
```

### Controller Test Example

```ruby
# test/controllers/autocomplete_controller_test.rb
test "returns JSON results for person search" do
  get autocomplete_search_path, params: { q: "boy", mode: "person_manage" }, as: :json

  assert_response :success
  json = JSON.parse(response.body)
  assert_equal "boy", json["query"]
  assert json["items"].is_a?(Array)
  assert json["flat_item_ids"].is_a?(Array)
end
```
