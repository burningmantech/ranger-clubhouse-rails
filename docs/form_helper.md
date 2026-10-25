# Form Helper Usage Guide

**Related Documentation:**
- [UI Components API Reference](UI-COMPONENTS.md) - Complete helper method signatures
- [Design Guide](DESIGN-GUIDE.md) - Design system and styling guide

## Overview

The `AppFormBuilder` is a custom Rails form builder that provides accessible, beautifully styled form fields with Tailwind CSS. It's designed specifically for the Clubhouse 3 application with a focus on usability, accessibility, and consistency.

### Design Principles

The form builder is built around five core design principles:

1. **Compact Layout** - Minimizes scrolling with efficient spacing
2. **WCAG 2.1 Level AA Compliance** - 36px minimum touch targets (`min-h-9`), above the 24px AA floor
3. **Clear Visual Hierarchy** - Visible labels and consistent field styling
4. **Strong Focus States** - Prominent keyboard navigation indicators
5. **Smooth Transitions** - Visual feedback for state changes

### Quick Start

The primary way to create forms is using the `ui_form` helper:

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Full Name", required: true %>
  <%= f.email_field :email, label: "Email Address" %>
  <%= f.submit "Save User" %>
<% end %>
```

This automatically:
- Uses `AppFormBuilder` for consistent styling
- Displays an error summary at the top if the model has errors
- Adds form controller for error focus management

## Layout Modes

AppFormBuilder supports three layout modes that control label positioning:

### Vertical Layout (Default)

Labels appear above their inputs. This is the default mode and works best for most forms.

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Full Name" %>
  <%= f.email_field :email, label: "Email" %>
<% end %>
```

### Horizontal Layout

Labels appear beside inputs on large screens, and stack vertically on mobile devices.

**Set at form level:**

```ruby
<%= ui_form(@user, users_path, layout: :horizontal) do |f| %>
  <%= f.text_field :name, label: "Full Name" %>
  <%= f.email_field :email, label: "Email" %>
<% end %>
```

**Override for individual fields:**

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Full Name", layout: :horizontal %>
  <%= f.email_field :email, label: "Email" %>
<% end %>
```

### Auto Layout

Automatically switches between vertical and horizontal based on screen size. On mobile (< 1024px), fields render with true vertical layout (labels above inputs). On desktop (>= 1024px), fields render with horizontal layout (labels beside inputs).

**Set at form level:**

```ruby
<%= ui_form(@user, users_path, layout: :auto) do |f| %>
  <%= f.text_field :name, label: "Full Name" %>
  <%= f.email_field :email, label: "Email" %>
<% end %>
```

**Override for individual fields:**

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Full Name", layout: :auto %>
  <%= f.email_field :email, label: "Email" %>
<% end %>
```

## Field Types

### Text-Based Input Fields

All standard HTML5 text input types are supported with consistent styling:

```ruby
# Basic text input
<%= f.text_field :name, label: "Full Name" %>

# Email with validation
<%= f.email_field :email, label: "Email Address", required: true %>

# Password field
<%= f.password_field :password, label: "Password" %>

# Number input
<%= f.number_field :age, label: "Age", min: 0, max: 120 %>

# URL field
<%= f.url_field :website, label: "Website" %>

# Telephone
<%= f.telephone_field :phone, label: "Phone Number" %>

# Search
<%= f.search_field :query, label: "Search", placeholder: "Enter search terms…" %>

# Date picker
<%= f.date_field :birth_date, label: "Date of Birth" %>

# Time picker
<%= f.time_field :start_time, label: "Start Time" %>

# Color picker
<%= f.color_field :favorite_color, label: "Favorite Color" %>
```

### DateTime Field with Calendar

The `datetime_field` integrates with Vanilla Calendar Pro for enhanced date/time selection:

```ruby
# With calendar picker (default)
<%= f.datetime_field :event_start, label: "Event Start" %>

# With custom calendar options
<%= f.datetime_field :event_start, 
  label: "Event Start",
  calendar_options: { 
    selectionTimeMode: 12,
    type: 'multiple'
  } %>

# Use native datetime input instead
<%= f.datetime_field :event_start, 
  label: "Event Start",
  use_calendar: false %>
```

### Textarea

Textareas default to full width and are vertically resizable:

```ruby
<%= f.text_area :bio, 
  label: "Biography",
  help_text: "Tell us about yourself",
  rows: 5 %>

# With character counter
<%= f.text_area :description,
  label: "Description",
  maxlength: 500,
  show_counter: true %>
```

### Rich Text Area

A formatted-text field — bold, italic, strikethrough, underline, headings (H2 to
H4), lists, quotes, code, links, tables and dividers — stored in the column as
HTML. Backed by the Lexxy editor, which only the pages that have one fetch (about
640KB, loaded by the `lexxy` Stimulus controller).

```ruby
<%= f.rich_text_area :message,
  label: "Message",
  required: true,
  help_text: "Keep it short. Bold the key point, and put steps in a list." %>
```

Renders a `<lexxy-editor>`, which is a form control in its own right: it submits
under its own field name (`motd[message]`), so no hidden input carries the value.
It takes the plain field id (`motd_message`), which is what the label points at.

Notes:

- **`required:` works.** The editor is form-associated, so it reports its own
  validity and the browser blocks submit like it does on any other field; Lexxy
  sets `aria-required` itself. Still validate on the model — an emptied editor
  submits empty blocks (`<p><br></p>`), which pass a plain `presence` check. A
  column that holds rich text should turn them into `""` on the way in, so
  `presence` and `.present?` mean what they say:

  ```ruby
  normalizes :body, with: BLANK_WHEN_EMPTY_RICH_TEXT   # defined on ApplicationRecord
  ```

  Empty means no words, which is how the editor itself decides it: an empty
  paragraph, list, heading, quote, code block or table, or a space typed in bold.
  A divider or an image is content. (`Motd` has its own check, which also refuses
  a message that is only a divider; see `message_says_something`.)

- **It starts 16rem tall** and grows with its text (`--lexxy-editor-rows` in
  `components/lexxy.css`). Lexxy's own `rows` attribute does not change that:
  the app's rule outranks it, and only browsers with typed `attr()` read it. A
  field that should start shorter sets the property in a class of its own, in
  rem rather than `lh` so the box keeps its size when iOS enlarges a focused
  field's text: the mailbox's reply box passes `class: "messages-reply-editor"`
  (6rem, about four lines; `components/messages.css`, owner-approved
  2026-10-18).

- **Rendering saved text** needs the `lexxy-content` class on the container,
  which gives paragraphs, lists, headings, quotes and tables their spacing and
  markers. Without it lists render as unmarked lines and a table has no borders.
  Sanitize on the way out with `rich_text` — the column holds whatever was
  posted, and the editor is only a client-side convenience. Rails' default
  safelist has no table tags, no `<s>` or `<u>`, and neither `colspan` nor
  `rowspan`, all of which Lexxy writes; `rich_text` adds them:

  ```erb
  <div class="lexxy-content"><%= rich_text(announcement.message) %></div>
  ```

  Documents an admin writes (agreements, the kiosk page) are the exception: they
  are printed as authored, and two of their pages have no `lexxy-content`
  container. A training resource document is cleaned when it is saved instead,
  because the people who write it are not admins.

- **The error state is a plain utility.** The vendored `lexxy-editor.css` and
  `components/lexxy.css` are both imported into `@layer components`, so the
  `border-error border-2` the helper adds wins without a `!`. The helper marks the
  editor `data-morph-skip`, so Turbo's morphing leaves the editor and its unsaved
  text alone; the guard in `app/javascript/application.js` still carries the
  server's classes onto it, so the border turns red after a rejected submit and
  goes again once the field is put right. What the server sent last is kept on
  the element as `data-server-class`, so the page the Back button returns to (a
  copy) still knows which classes to take off.
- **Images are not kept.** Uploads are off (`attachments="false"`): the toolbar
  has no upload buttons, and a pasted or dropped file is ignored. Lexxy also
  drops every `<img>` in text it is handed, so saving text that has one removes
  it. The helper says so on the form, in a warning above the editor, and takes the
  image out of what the editor loads (left in, it is dropped with the spaces on
  either side of it). The warning counts the images in the saved text, so it is
  still there when the form comes back from a rejected save. An image pasted in
  with other text is dropped as it is pasted, and there the words either side of
  it do close up; the author sees that happen.
- **What a save changes in older text.** The editor rewrites what it loads, even
  when nothing is typed. Kept: paragraphs, headings, lists, quotes, links, tables
  with merged cells, dividers. Changed: `<div>` blocks become `<p>`; coloured text
  becomes `<mark style="color: …">`; a link written relative to a folder
  (`docs/map.pdf`) is kept by the helper as `./docs/map.pdf`. Lost: images, a
  table's `<caption>`, link `target` and `rel`, alignment and font sizes, and the
  address of a link whose scheme is not http, https, mailto, sms or tel. A bare
  `map.pdf` or `example.org/page` gets `https://` put in front of it.
- **Markdown is on.** Typing `- `, `1. `, `> `, three backticks or `---` starts
  the matching block, and Markdown that is pasted is converted. `# ` to `###### `
  make any heading level, H1 and H6 included, though the toolbar offers H2 to H4.
- **Pasting from Google Docs keeps bold, italic and underline.** Lexxy alone
  drops them; `lexxy_controller.js` adds the two small extensions that keep them
  and keep merged table cells. A paste the first one takes goes in through
  Lexxy's own `contents.insertDOM`, so it also gets Lexxy's clean-up of pasted
  HTML; any other paste is Lexical's default, as before.
- **Lexxy's own controls are not fields of the form.** Its link box and its code
  language list sit inside the editor, so inside the form. `lexxy_controller.js`
  gives each an empty `form` attribute: otherwise an address left in the closed
  link box fails the browser's check and Save does nothing, and the language list
  is posted with every form.
- **The Back button brings a draft back.** Lexxy empties itself when Turbo takes
  its snapshot of a page. `lexxy_controller.js` writes the typed text into the
  `value` attribute first, so the snapshot holds it, and rebuilds the editor when
  the page turns out not to have been replaced (a move to a place on the same
  page, basecamp/lexxy#1200).
- **One editor per attribute per page.** The editor takes the field's id and
  name, so two for the same attribute share both.
- Untested with `icon:`, `show_counter:`, `disabled:` and nested-form names.
- Coloured text and the code language picker are hidden in
  `components/lexxy.css`: coloured text is not part of the design system. A
  divider has no on-screen remove control (Lexxy keeps it with its attachment
  tools, which are off): select it and press Backspace.
- Styling lives in three vendored sheets (`lexxy-variables.css`,
  `lexxy-content.css`, `lexxy-editor.css`) and
  `app/assets/stylesheets/components/lexxy.css`, which points Lexxy's
  `--lexxy-*` variables at the app's tokens, so both themes are covered. The
  vendored sheets are the gem's, less their first line; re-theme in
  `components/lexxy.css`, never in place. Upgrading Lexxy is a copy of four files
  and that one deletion; see the comment in `config/importmap.rb`.

### Select Fields

**Basic select with options:**

```ruby
<%= f.select :status, 
  ["Active", "Inactive", "Pending"],
  { label: "Status" } %>

# With include_blank
<%= f.select :role,
  ["Admin", "Manager", "User"],
  { label: "Role", include_blank: "Select a role…" } %>
```

**Collection select from ActiveRecord:**

```ruby
<%= f.collection_select :department_id,
  Department.all,
  :id,
  :name,
  { label: "Department" } %>
```

### Checkbox Fields

**Single checkbox:**

```ruby
# With inline label
<%= f.check_box :agree_to_terms, 
  inline_label: "I agree to the terms and conditions" %>

# With separate label and help text
<%= f.check_box :newsletter,
  label: "Email Preferences",
  inline_label: "Send me the newsletter",
  help_text: "You can unsubscribe at any time" %>
```

### Radio Buttons

**Individual radio buttons:**

```ruby
<%= f.radio_button :status, "active", label: "Active" %>
<%= f.radio_button :status, "inactive", label: "Inactive" %>
```

**Collection radio buttons:**

```ruby
# Vertical layout (default)
<%= f.collection_radio_buttons :role_id,
  Role.all,
  :id,
  :name,
  { label: "Select Role" } %>

# Horizontal layout
<%= f.collection_radio_buttons :status,
  [["Active", "active"], ["Inactive", "inactive"]],
  :last,
  :first,
  { label: "Status", layout: :horizontal } %>

# Stacked group label (label on its own line, radios below)
# Useful for long labels or desktop layouts that need more space
<%= f.collection_radio_buttons :priority,
  Priority.all,
  :id,
  :name,
  { label: "Select Priority Level", layout: :horizontal, label_position: :stacked } %>
```

#### Group Label Positioning

For `collection_radio_buttons` with `:horizontal` or `:auto` layouts, you can control whether the group label appears inline with the radio buttons or on its own line above them:

**`:inline` (default)** - Label appears beside the radio button group:
```ruby
<%= f.collection_radio_buttons :status,
  Status.all,
  :id,
  :name,
  { label: "Status", layout: :horizontal } %>
# Renders as: [Status] (•) Active (•) Inactive
```

**`:stacked`** - Label appears on its own line above the radio buttons:
```ruby
<%= f.collection_radio_buttons :status,
  Status.all,
  :id,
  :name,
  { label: "Status", layout: :horizontal, label_position: :stacked } %>
# Renders as:
# Status
# (•) Active (•) Inactive
```

**When to use `:stacked`:**
- Long label text that doesn't fit well inline
- Desktop layouts where horizontal space is limited
- Forms with consistent stacked label patterns

**Important notes:**
- `label_position` only affects `:horizontal` and `:auto` layouts
- Vertical layout always uses `fieldset`/`legend` structure (semantic HTML)
- The `layout` option still controls radio button orientation (horizontal vs vertical)
- Invalid values fall back to `:inline`

### File Upload

```ruby
<%= f.file_field :avatar, 
  label: "Profile Picture",
  accept: "image/*" %>

# Multiple files
<%= f.file_field :documents,
  label: "Upload Documents",
  multiple: true %>
```

### Fieldset Grouping

Group related fields with a fieldset and legend:

```ruby
<%= f.fieldset "Contact Information" do %>
  <%= f.email_field :email, label: "Email" %>
  <%= f.telephone_field :phone, label: "Phone" %>
<% end %>

# With icon
<%= f.fieldset "Account Settings", icon: "user", icon_type: :solid do %>
  <%= f.text_field :username, label: "Username" %>
  <%= f.password_field :password, label: "Password" %>
<% end %>

# With block legend for complex content
<%= f.fieldset do |legend| %>
  <% legend.legend do %>
    <strong>Advanced Options</strong>
    <span class="text-sm">(optional)</span>
  <% end %>
  
  <%= f.check_box :enable_notifications, inline_label: "Enable notifications" %>
<% end %>
```

A fieldset around controls the builder does not label (a checkbox list, repeated
`select_tag` rows) draws its own help and error lines with the builder's public
`help_text_tag(text, id)` and `error_message(attribute, id)`, and points the
fieldset's `aria-describedby` at their ids (`app/views/admin/shift_coverage_groups/_form.html.erb`):

```erb
<%= f.fieldset "Period Positions",
               aria: { describedby: token_list("base-positions-help",
                                               "base-positions-error": @group.errors.include?(:base_position_ids)) } do %>
  <%= f.help_text_tag "Each shift of these positions becomes one period.", "base-positions-help" %>
  <%= f.error_message :base_position_ids, "base-positions-error" %>
  ...
<% end %>
```

`error_message` joins an attribute's messages with a space when every one ends in
`.`, `!` or `?` (the app's messages are whole sentences), and with ", " otherwise.

## Common Field Options

All field types support these common options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `label:` | String | - | Label text displayed above/beside the field |
| `help_text:` | String | - | Help text displayed below the field |
| `help_mode:` | Symbol | `:inline` | Display mode: `:inline` or `:tooltip` |
| `required:` | Boolean | `false` | Adds required indicator (*) and HTML5 required attribute |
| `width:` | String | `"w-auto"` | Tailwind width class (e.g., `"w-full"`, `"w-1/2"`) |
| `layout:` | Symbol | Form default | Override layout for this field: `:vertical`, `:horizontal`, or `:auto` |
| `wrapper_class:` | String | - | Additional CSS classes for the wrapper div |
| `wrapper:` | Boolean | `true` | Set to `false` to skip the wrapper div |
| `wrapper_id:` | String | - | ID attribute for the wrapper div |
| `hidden:` | Boolean | `false` | Hide the field wrapper (adds `hidden` class) |
| `hide_label:` | Boolean | `false` | Visually hide the label (still accessible to screen readers) |
| `icon:` | String | - | FontAwesome icon name for prefix icon |
| `icon_type:` | Symbol | `:solid` | Icon style: `:solid` or `:regular` (Free styles only) |
| `show_counter:` | Boolean | `false` | Show character counter (requires `maxlength` attribute) |
| `replace_class:` | Boolean | `false` | Replace default styling classes entirely |
| `label_position:` | Symbol | `:inline` | **For `collection_radio_buttons` only**: `:inline` (label beside radios) or `:stacked` (label on its own line above radios). Only applies to `:horizontal` and `:auto` layouts. |

### Examples Using Common Options

```ruby
# Required field with help text
<%= f.text_field :username,
  label: "Username",
  required: true,
  help_text: "Must be 3-20 characters" %>

# Field with icon prefix
<%= f.email_field :email,
  label: "Email",
  icon: "envelope",
  icon_type: :solid %>

# Tooltip help text
<%= f.password_field :password,
  label: "Password",
  help_text: "Must contain at least 8 characters, one uppercase, one number",
  help_mode: :tooltip %>

# Custom width
<%= f.text_field :zip_code,
  label: "ZIP Code",
  width: "w-32" %>

# Hidden field wrapper (for conditional display)
<%= f.text_field :other_reason,
  label: "Please specify",
  hidden: true,
  wrapper_id: "other_reason_wrapper" %>

# Character counter
<%= f.text_area :bio,
  label: "Bio",
  maxlength: 500,
  show_counter: true %>
```

## Helper Methods

### ui_form

The primary helper for creating forms with automatic error handling:

```ruby
ui_form(model, url, options = {}, &block)
```

**Options:**
- `no_error_summary: true` - Skip the automatic error summary
- `layout: :horizontal` - Set default layout for all fields
- All standard `form_with` options

**Example:**

```ruby
<%= ui_form(@user, users_path, layout: :horizontal) do |f| %>
  <%= f.text_field :name, label: "Name" %>
  <%= f.submit "Save" %>
<% end %>

# Skip error summary
<%= ui_form(@user, users_path, no_error_summary: true) do |f| %>
  <!-- fields -->
<% end %>
```

### form_row

Place multiple fields side by side in a responsive row:

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= form_row do %>
    <%= f.text_field :first_name, label: "First Name" %>
    <%= f.text_field :last_name, label: "Last Name" %>
  <% end %>
<% end %>

# Custom classes
<%= form_row(class: "gap-6") do %>
  <%= f.text_field :city, label: "City" %>
  <%= f.text_field :state, label: "State", width: "w-32" %>
  <%= f.text_field :zip, label: "ZIP", width: "w-32" %>
<% end %>
```

### form_error_summary

Manually display error summary (automatically included in `ui_form`):

```ruby
<%= form_error_summary(@user) %>
```

### input_counter_data

Generate data attributes for character counters (useful for custom inputs):

```ruby
<%= text_field_tag :comment, "", 
  maxlength: 200,
  data: input_counter_data %>
```

## Error Handling

The form builder provides automatic error handling with visual feedback:

### Automatic Error Display

When a model has validation errors:

1. **Error Summary** - Displayed at the top of the form (unless `no_error_summary: true`)
2. **Field Styling** - Error fields get red border and background
3. **Error Messages** - Displayed below each field with errors
4. **ARIA Attributes** - Proper `aria-describedby` linking for screen readers

```ruby
# This automatically shows errors if @user.errors.any?
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :email, label: "Email" %>
  <%= f.submit "Save" %>
<% end %>
```

### Error States

Fields automatically detect errors from the model's `errors` object:

```ruby
@user = User.new(email: "invalid")
@user.valid?  # false, email format error

# The email field will automatically:
# - Show red border and background
# - Display the error message below the field
# - Add aria-describedby for accessibility
```

### Customizing Error Display

```ruby
# Hide the error summary but keep field-level errors
<%= ui_form(@user, users_path, no_error_summary: true) do |f| %>
  <%= f.text_field :email, label: "Email" %>
<% end %>

# Manual error summary placement
<div class="custom-location">
  <%= form_error_summary(@user) %>
</div>

<%= form_with model: @user, url: users_path, builder: AppFormBuilder do |f| %>
  <%= f.text_field :email, label: "Email" %>
<% end %>
```

## Accessibility Features

AppFormBuilder is built with WCAG 2.1 Level AA compliance:

### Keyboard Navigation

- **Focus Rings** - Prominent 2px brand-colored ring for all interactive elements
- **Logical Tab Order** - Natural flow through form fields
- **Skip Links** - Compatible with standard skip navigation patterns

### Screen Reader Support

- **Proper Labels** - All fields have associated `<label>` elements
- **ARIA Attributes** - `aria-describedby` links fields to help text and errors
- **Role Attributes** - Error messages use `role="alert"`
- **Hidden Required Text** - Screen reader-only text announces required fields

### Touch Targets

- **Minimum 36px** - Every control, or the label that wraps it, carries `min-h-9`, above WCAG 2.5.8's 24px floor
- **Checkbox/Radio** - 18px inputs inside a `min-h-9` label, so the label is the tap area

### Visual Indicators

- **Required Fields** - Red asterisk (*) with hidden "(required)" text
- **Error States** - Color plus icon indicators (not color alone)
- **Focus States** - Visible focus indicators for keyboard users

### Example Accessible Form

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%# Required field with screen reader announcement %>
  <%= f.text_field :name, 
    label: "Full Name", 
    required: true %>
  
  <%# Field with help text linked via aria-describedby %>
  <%= f.email_field :email,
    label: "Email Address",
    help_text: "We'll never share your email with anyone" %>
  
  <%# Radio group with proper fieldset/legend %>
  <%= f.collection_radio_buttons :role,
    Role.all,
    :id,
    :name,
    { label: "Select your role" } %>
  
  <%# Checkbox with clear label association %>
  <%= f.check_box :newsletter,
    inline_label: "I want to receive the newsletter" %>
<% end %>
```

## Styling and Customization

### Default Styling

All fields use Tailwind CSS with a consistent design system:

- **Base Colors** - Neutral backgrounds, default borders
- **Error Colors** - Danger palette for validation errors
- **Brand Colors** - Brand blue for focus states and checked toggles
- **Typography** - Consistent text sizes and line heights

### Custom Width

Override the default `w-auto` width for specific fields:

```ruby
<%= f.text_field :name, label: "Name", width: "w-full" %>
<%= f.text_field :zip, label: "ZIP", width: "w-32" %>
<%= f.text_area :notes, label: "Notes" %> <%# Textareas default to w-full %>
```

### Custom Wrapper Classes

Add additional classes to field wrappers:

```ruby
<%= f.text_field :secret,
  label: "Secret Field",
  wrapper_class: "border-l-4 border-primary pl-4" %>
```

### Replace Default Classes

For complete custom styling (e.g., dark theme contexts):

```ruby
<%= f.text_field :name,
  label: "Name",
  replace_class: true,
  class: "bg-neutral text-neutral-content border border-line rounded px-4 py-2" %>
```

### Icon Prefixes

Add FontAwesome icons to text inputs:

```ruby
<%= f.email_field :email,
  label: "Email",
  icon: "envelope",
  icon_type: :solid %>

<%= f.search_field :query,
  label: "Search",
  icon: "magnifying-glass" %>
```

## Complete Examples

### Simple User Profile Form

```ruby
<%= ui_form(@user, user_path(@user), method: :patch) do |f| %>
  <%= form_row do %>
    <%= f.text_field :first_name, label: "First Name", required: true %>
    <%= f.text_field :last_name, label: "Last Name", required: true %>
  <% end %>
  
  <%= f.email_field :email, 
    label: "Email Address",
    icon: "envelope",
    required: true %>
  
  <%= f.telephone_field :phone,
    label: "Phone Number",
    icon: "phone",
    help_text: "Format: (555) 555-5555" %>
  
  <%= f.text_area :bio,
    label: "Biography",
    help_text: "Tell us about yourself",
    maxlength: 500,
    show_counter: true,
    rows: 4 %>
  
  <%= f.submit "Save Profile" %>
<% end %>
```

### Registration Form with Validation

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.fieldset "Account Information", icon: "user" do %>
    <%= f.text_field :username,
      label: "Username",
      required: true,
      help_text: "3-20 characters, letters and numbers only" %>
    
    <%= f.email_field :email,
      label: "Email Address",
      icon: "envelope",
      required: true %>
    
    <%= f.password_field :password,
      label: "Password",
      required: true,
      help_text: "Minimum 8 characters",
      help_mode: :tooltip %>
    
    <%= f.password_field :password_confirmation,
      label: "Confirm Password",
      required: true %>
  <% end %>
  
  <%= f.fieldset "Profile Details", icon: "id-card" do %>
    <%= form_row do %>
      <%= f.text_field :first_name, label: "First Name", required: true %>
      <%= f.text_field :last_name, label: "Last Name", required: true %>
    <% end %>
    
    <%= f.date_field :birth_date, label: "Date of Birth" %>
    
    <%= f.file_field :avatar,
      label: "Profile Picture",
      accept: "image/*",
      help_text: "JPG or PNG, max 2MB" %>
  <% end %>
  
  <%= f.fieldset "Preferences" do %>
    <%= f.check_box :newsletter,
      inline_label: "Send me the monthly newsletter" %>
    
    <%= f.check_box :terms,
      inline_label: "I agree to the terms and conditions",
      required: true %>
  <% end %>
  
  <%= f.submit "Create Account" %>
<% end %>
```

### Search Form with Horizontal Layout

```ruby
<%= ui_form(@search, search_path, method: :get, layout: :horizontal) do |f| %>
  <%= f.search_field :query,
    label: "Search",
    icon: "magnifying-glass",
    placeholder: "Enter keywords…",
    width: "w-full" %>
  
  <%= f.select :category,
    Category.pluck(:name, :id),
    { 
      label: "Category",
      include_blank: "All Categories"
    } %>
  
  <%= f.collection_radio_buttons :status,
    [["Active", "active"], ["Archived", "archived"], ["All", "all"]],
    :last,
    :first,
    {
      label: "Status",
      layout: :horizontal
    } %>
  
  <%= f.date_field :from_date, label: "From Date" %>
  <%= f.date_field :to_date, label: "To Date" %>
  
  <div class="lg:ml-[25%] flex gap-2">
    <%= f.submit "Search" %>
    <%= link_to "Clear", search_path, class: button_classes(type: :secondary) %>
  </div>
<% end %>
```

## Advanced Usage

### Conditional Fields

Show/hide fields based on other selections:

```ruby
<%= ui_form(@user, users_path) do |f| %>
  <%= f.select :contact_method,
    ["Email", "Phone", "Other"],
    { label: "Preferred Contact Method" },
    { data: { 
      action: "change->visibility#toggle",
      visibility_target_value: "#other_method_wrapper"
    }} %>
  
  <%= f.text_field :other_method,
    label: "Please specify",
    hidden: true,
    wrapper_id: "other_method_wrapper" %>
<% end %>
```

### Dynamic Character Counters

```ruby
<%= f.text_area :description,
  label: "Description",
  maxlength: 1000,
  show_counter: true,
  help_text: "Provide a detailed description" %>
```

The counter automatically appears and updates as the user types.

### Multiple Submit Buttons

```ruby
<%= ui_form(@post, posts_path) do |f| %>
  <%= f.text_field :title, label: "Title" %>
  <%= f.text_area :body, label: "Body" %>
  
  <div class="flex gap-2">
    <%= f.submit "Publish", name: "commit", value: "publish" %>
    <%= f.submit "Save Draft", 
      name: "commit", 
      value: "draft",
      formnovalidate: true,
      data: { button_type_value: :secondary } %>
  </div>
<% end %>
```

---

## Reference

### Constants

Key styling constants defined in `AppFormBuilder`:

- `VALID_LAYOUTS` - `[:vertical, :horizontal, :auto]`
- `DEFAULT_WIDTH_CLASSES` - `"w-auto"`
- `TEXTAREA_DEFAULT_WIDTH` - `"w-full"`
- `TOGGLE_SIZE` - `"w-[18px] h-[18px]"`

### Related Files

- `app/helpers/form_helper.rb` - Main form builder implementation
- `app/helpers/ui_components/ui_form_helper.rb` - `ui_form`, the form wrapper
- `app/javascript/controllers/form_controller.js` - Form behavior (error focus)
- `app/javascript/controllers/input_counter_controller.js` - Character counter
- `app/javascript/controllers/vanilla_calendar_controller.js` - Date/time picker
