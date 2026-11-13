---
name: design-forms
description: Form builder patterns and field helpers for Clubhouse 3. Use when creating forms, form fields, handling validation, or implementing multi-section form pages.
---

# Design Forms

## Form Builder

**Builder**: `AppFormBuilder` (`app/helpers/form_helper.rb`)

**CRITICAL:** Always use `ui_form` or `AppFormBuilder` for forms. The form builder ensures WCAG 2.1 Level AA compliance and ADHD-friendly patterns.
**CRITICAL:** Do not warn about the delete button or link being nested within the form. Ruby On Rails handles this situation correctly.
**CRITICAL:** Place the delete button inline with the save/update and cancel buttons

### Basic Usage

```erb
<%# Using ui_form helper (recommended) %>
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Full Name", required: true %>
  <%= f.email_field :email, label: "Email Address", help_text: "We'll never share this" %>
  
  <%= button_row do %>
    <%= f.submit "Save" %>
    <%= cancel_button users_path %>
    <% if @user.persisted? %>
       <%= delete_button user_path(@user) %>
    <% end %>
  <% end %>
<% end %>

<%# Or using form_with directly %>
<%= form_with model: @user, builder: AppFormBuilder do |f| %>
  <%= f.text_field :name, label: "Name" %>
<% end %>
```

Not covered by the builder: a fieldless carrier form (a hidden `form_tag` that only gives buttons
somewhere to submit) and a filter input that never submits (`search_field_tag` filtering a list in
the browser), which still has a visible label or an `aria-label`.

---

## Layout Modes

```erb
<%# Vertical layout (default) - Best for mobile and accessibility %>
<%= ui_form(@user, users_path) do |f| %>
  <%= f.text_field :name, label: "Name" %>
<% end %>

<%# Horizontal layout - Better for desktop dense forms %>
<%= ui_form(@user, users_path, layout: :horizontal) do |f| %>
  <%= f.text_field :name, label: "Name" %>
<% end %>

<%# Auto layout - Vertical on mobile, horizontal on desktop (lg: breakpoint) %>
<%= ui_form(@user, users_path, layout: :auto) do |f| %>
  <%= f.text_field :name, label: "Name" %>
<% end %>

<%# Per-field layout override %>
<%= f.text_field :name, label: "Name", layout: :horizontal %>
<%= f.text_field :name, label: "Name", layout: :auto %>

<%# Side-by-side fields with form_row %>
<%= form_row do %>
  <%= f.text_field :first_name, label: "First", wrapper_class: "flex-1" %>
  <%= f.text_field :last_name, label: "Last", wrapper_class: "flex-1" %>
<% end %>
```

---

## Field Options

All fields support these common options:

| Option | Type | Description |
|--------|------|-------------|
| `label:` | String | Label text (always use - never placeholder-only) |
| `required:` | Boolean | Shows "(required)" after the label (`text-sm`, error colour) and adds the `required` attribute; every field, `check_box` included |
| `help_text:` | String | Supportive text below the field |
| `layout:` | Symbol | `:vertical`, `:horizontal`, or `:auto` |
| `wrapper_class:` | String | Custom classes for wrapper div |
| `width:` | String | Custom width classes (e.g., `"w-32"` or `"w-full sm:w-48"`) |
| `hidden:` | Boolean | Adds `hidden` class to wrapper |
| `maxlength:` | Integer | Defaults to what a model attribute can store: its own length rule, else its varchar column. None for a text column with no rule, a password or telephone field, or a form object. Set it only for a smaller limit; `nil` leaves it off |
| `show_counter:` | Boolean | Display character counter for fields with `maxlength` |
| `label_position:` | Symbol | **For `collection_radio_buttons` only**: `:inline` (default, label beside radios) or `:stacked` (label on its own line above radios). Only applies with `:horizontal` or `:auto` layout. |

---

## Field Types

```erb
<%# Text inputs %>
<%= f.text_field :name, label: "Name", required: true %>
<%= f.email_field :email, label: "Email" %>
<%= f.password_field :password, label: "Password" %>
<%= f.number_field :age, label: "Age" %>
<%= f.telephone_field :phone, label: "Phone" %>
<%= f.url_field :website, label: "Website" %>
<%= f.search_field :query, label: "Search" %>

<%# Text input with character counter: the maxlength comes from the record %>
<%= f.text_field :callsign, label: "Callsign", show_counter: true %>

<%# Text input with responsive width %>
<%= f.text_field :preferred_name, label: "Preferred Name", width: "w-full sm:w-48" %>

<%# Date/Time %>
<%= f.datetime_field :starts_at, label: "Start Time" %>
<%= f.date_field :birth_date, label: "Birth Date" %>
<%= f.time_field :reminder, label: "Reminder Time" %>

<%# Textarea (daisyUI's 80px minimum height, full width by default) %>
<%= f.text_area :bio, label: "Biography", help_text: "Tell us about yourself" %>
<%= f.text_area :reason, label: "Reason", maxlength: 1000, show_counter: true %>

<%# Select %>
<%= f.select :role, [["Admin", "admin"], ["User", "user"]], { label: "Role" } %>
<%= f.collection_select :department_id, @departments, :id, :name, { label: "Department" } %>

<%# Checkboxes (36px tap target) %>
<%= f.check_box :terms, label: "I agree to the terms of service" %>
<%= f.check_box :newsletter, label: "Subscribe to newsletter", help_text: "Weekly updates" %>

<%# Radio buttons (36px tap target) %>
<%= f.radio_button :status, "active", label: "Active" %>
<%= f.radio_button :status, "inactive", label: "Inactive" %>

<%# Collection radio buttons - default vertical layout %>
<%= f.collection_radio_buttons :priority, Priority.all, :id, :name, { label: "Priority" } %>

<%# Collection radio buttons - horizontal with inline label (default) %>
<%= f.collection_radio_buttons :status, Status.all, :id, :name,
    { label: "Status", layout: :horizontal } %>

<%# Collection radio buttons - horizontal with stacked label %>
<%= f.collection_radio_buttons :status, Status.all, :id, :name,
    { label: "Status", layout: :horizontal, label_position: :stacked } %>

<%# File upload (styled upload button) %>
<%= f.file_field :avatar, label: "Profile Photo" %>
```

---

## Collection Radio Button Label Positioning

For `collection_radio_buttons` with `:horizontal` or `:auto` layouts, use `label_position` to control label placement:

- **`:inline` (default)**: Label appears beside the radio group - best for short labels
- **`:stacked`**: Label on its own line above radios - best for long labels or limited horizontal space

**When to use `:stacked`:**
- Long label text that doesn't fit well inline
- Desktop layouts where horizontal space is limited
- Forms with consistent stacked label patterns

**Important:** `label_position` only affects `:horizontal` and `:auto` layouts. The `layout` option still controls radio button orientation.

```erb
<%# Inline - good for short labels %>
<%= f.collection_radio_buttons :status,
    [["Active", "active"], ["Inactive", "inactive"]],
    :last, :first,
    { label: "Status", layout: :horizontal } %>

<%# Stacked - better for longer labels %>
<%= f.collection_radio_buttons :notification_preference,
    NotificationPreference.all, :id, :display_name,
    { label: "How would you like to receive notifications?",
      layout: :horizontal,
      label_position: :stacked } %>
```

---

## Form Grouping: Fieldsets vs UI Sections

### When to Use `f.fieldset`

Best for semantic grouping of form controls with compact layout:

**Appropriate use cases:**
- Radio button and checkbox groups (semantic HTML standard)
- Correction/request forms with multiple distinct sections
- Forms where visual density is beneficial
- Related fields that need compact presentation

**Caution:** Screen readers announce the legend text for every input when tabbing through the fieldset.

**Styling** (`components/forms.css`): a 4px `border-primary` start rule over a `from-primary/5`
gradient, `rounded-r-lg`; the legend `text-lg font-semibold` over a `border-base-200` underline.

```erb
<%= f.fieldset "Personal Information" do %>
  <%= f.text_field :first_name, label: "First Name", required: true %>
  <%= f.text_field :last_name, label: "Last Name", required: true %>
  <%= f.email_field :email, label: "Email Address", required: true %>
<% end %>

<%# With icon %>
<%= f.fieldset "Vehicle Description", icon: "car", icon_type: :solid do %>
  <%= f.select :vehicle_class, Vehicle::CLASS_OPTIONS, label: "Vehicle Class" %>
  <%= f.text_field :vehicle_make, label: "Make" %>
<% end %>

<%# With Q&A explanations %>
<%= f.fieldset "Contact Information" do %>
  <dl class="instruction-list mb-3">
    <dt>Why do we need this?</dt>
    <dd>Used to contact you if email fails.</dd>
  </dl>
  <%= f.text_field :phone, label: "Phone Number" %>
<% end %>
```

### When to Use `ui_section`

Best for card-based grouping with generous whitespace and ADHD-friendly design:

**Appropriate use cases:**
- Profile edit forms with multiple logical sections
- Forms requiring extensive explanatory content
- User-facing editable profile data
- When visual distinction and breathing room are priorities

```erb
<%= ui_form(@person, path) do |f| %>
  <%= ui_section "Legal Name", icon: "id-card", icon_type: :solid do %>
    <dl class="instruction-list mb-3">
      <dt>Why do we need this?</dt>
      <dd>Used for ticketing, mailings, and Motor Vehicle Record requests.</dd>
    </dl>
    <%= form_row do %>
      <%= f.text_field :first_name, label: "First Name", width: "w-full sm:w-48" %>
      <%= f.text_field :last_name, label: "Last Name", width: "w-full sm:w-48" %>
    <% end %>
  <% end %>
<% end %>
```

---

## Error States

Errors are automatically displayed with ADHD-friendly prominence:

- **Field highlighting**: daisyUI `input-error` (error border and tint, both themes)
- **Error badge**: Small red circle with "!" for visual scanning
- **Error messages**: Displayed below field with `role="alert"` for screen readers
- **Label color change**: Red label indicates which field needs attention
- **Error summary**: `ui_form` shows all errors at top in callout box
- **Automatic focus**: First error field receives focus automatically on validation failure

```erb
<%# Error summary is automatic with ui_form %>
<%= ui_form(@user, users_path) do |f| %>
  <%# Fields with errors automatically show error styling %>
  <%= f.text_field :email, label: "Email" %>
<% end %>

<%# Skip error summary if desired %>
<%= ui_form(@user, users_path, no_error_summary: true) do |f| %>
  ...
<% end %>
```

**Forms without one model.** A form with no model, or one that acts on many records (a bulk tool,
an editable grid, a paste-then-review flow), reports a refusal in a `ui_callout_box :error` above
the form or in its results (`:warning` when only some rows failed), naming the rows that failed; a
flash alone is not enough. A per-line review table counts as that report.

---

## ADHD-Friendly Form Page Patterns

### Form Page Structure

Standard structure for edit form pages. The order is fixed: hero (title, and a back link when the
reader came from a page in the app; a description is optional on a new or edit page), optional
callouts, `ui_form`, and the button row last. The rest is free: a short form may put its fields
straight in `ui_form`, a `ui_section` may box the whole form, a callout that explains one group of
fields may sit inside the form beside them, and an edit form may have a stat row above it.

```erb
<%# 1. Hero Panel with description and back navigation %>
<%= hero_panel icon: "icon-name", heading_level: :h1, id: "page-id" do |panel| %>
  <% panel.title do %>Edit [Entity Name]<% end %>
  <% panel.description do %>Brief summary of what can be edited.<% end %>
  <% panel.back_to do %><%= back_to "Parent Page", parent_path %><% end %>
<% end %>

<%# 2. Contextual callouts (if needed) %>
<%= ui_callout_box :info, icon: "lightbulb", icon_type: :solid do %>
  <strong>Lead with the key point.</strong> Supporting details follow.
<% end %>

<%# 3. Form with sectioned content %>
<%= ui_form(@model, submit_path) do |f| %>
  <%= ui_section "Section Title", icon: "icon-name", icon_type: :solid do %>
    <%# Q&A explanation + fields %>
  <% end %>
  <%# Sticky action buttons %>
<% end %>
```

### Q&A Style Explanations

Replace paragraphs with scannable Q&A format:

```erb
<dl class="instruction-list mb-3">
  <dt>Why do we need this?</dt>
  <dd>Concise answer in one sentence.</dd>
  <dt>Is this required?</dt>
  <dd>No, this field is optional.</dd>
</dl>
```

**Common questions to answer:**

| Question | Purpose |
|----------|---------|
| "Why do we need this?" | Explain purpose |
| "Is this required?" | Clarify optionality |
| "What happens if...?" | Address concerns |
| "Where is this used?" | Explain visibility |

### Field Width Guidelines

Constrain field widths based on expected content. **Always use responsive width classes**:

| Field Type | Width Class | Notes |
|------------|-------------|-------|
| Names (first/last) | `w-full sm:w-48` | Responsive for mobile |
| Middle initials | `w-20` | Small enough for mobile |
| Phone numbers | `w-full sm:w-44` | Responsive for mobile |
| Email addresses | `w-full sm:w-72` | Responsive for mobile |
| Short text | `w-full sm:w-64` | Responsive for mobile |
| Select dropdowns | `w-full sm:w-44` | Responsive for mobile |

**Mobile-First Approach:**
- Use `w-full` for mobile to prevent horizontal scrolling
- Add `sm:` prefix for desktop widths (640px and above)
- Fields narrower than `w-32` don't need responsive classes
- `sm:` is otherwise an AVOID breakpoint (`design-layouts`); field `width:` is its one sanctioned use
- The table is for a field standing alone. In a `filter_bar` panel or a `form_row` of fields side by
  side, each field fills its share (`width: "w-full"`, `wrapper_class: "flex-1"`) or keeps the default
- A width goes through `width:`, never the input's `class:`, and turns at `sm:` on a scale step:
  never `lg:` (`lg:w-96`) or an arbitrary value (`lg:w-[40rem]`)

```erb
<%= f.text_field :preferred_name, label: "Preferred Name", width: "w-full sm:w-48" %>
<%= f.text_field :email, label: "Email", width: "w-full sm:w-72" %>
<%= f.text_field :mi, label: "Middle Initial", width: "w-20" %>
```

### Conditional Field Layout

When a select triggers a custom text field:

```erb
<div class="flex flex-col lg:flex-row lg:items-start gap-2 lg:gap-4">
  <%= f.select :field, OPTIONS, { label: "Label" },
      { class: "w-44", data: { controller: "conditional-show", ... } } %>
  <%= f.text_field :custom_field, label: "Custom Value",
      width: "w-64", wrapper_id: "custom-block", hidden: !show_custom? %>
</div>
```

### Sticky Save Button (Mobile)

Keep save/cancel buttons accessible on mobile:

```erb
<%= button_row do %>
  <%= f.submit "Save Changes" %>
  <%= cancel_link back_path %>
<% end %>
```

**Behavior:**
- Mobile: Fixed to bottom of viewport with opaque background
- Desktop (`lg:` breakpoint): Normal static positioning

---

## Accessibility Features

The form builder includes built-in accessibility:

- **Labels**: Always visible, properly associated via `for` attribute. In a grid of rows the column
  heading is the visible label; each field takes `hide_label:` and an `aria-label` naming row and column
- **Required fields**: the visible word "(required)" in the label (`text-sm`, error colour), which
  screen readers read with it, and the `required` attribute
- **Help text**: Connected via `aria-describedby`
- **Error messages**: Use `role="alert"` for screen reader announcement
- **Focus states**: High-contrast 2px ring with offset, meets WCAG 2.4.7
- **Touch targets**: Minimum 36px height for all interactive elements
- **Keyboard navigation**: Full support with visible focus indicators

---

## Related Skills

- **design-rules**: Critical rules and approval workflows
- **design-foundations**: Colors, typography, spacing for forms
- **design-components**: Button helpers, sections, callouts
- **design-layouts**: Form page layout patterns
- **design-content**: ADHD-friendly content and terminology

## Full Documentation

For complete documentation, see:
- [docs/DESIGN-GUIDE.md](../../docs/DESIGN-GUIDE.md) - Form Patterns section
- [docs/form_helper.md](../../docs/form_helper.md) - Complete form builder API
