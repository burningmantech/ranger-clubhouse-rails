---
name: project-standards
description: Coding standards, development philosophy, and critical rules for Clubhouse 3 development. Use when writing code, reviewing solutions, translating code, making architectural decisions, or implementing features.
---

# Clubhouse 3 - Project Standards

## Core Development Philosophy

Prioritize solutions with:
- Economy of motion and minimal effort
- Surgical precision - no unnecessary changes
- No moving parts or knobs to tweak
- Adherence to existing coding standards and best practices
- Use of already-installed packages when possible
- Latest versions of widely-adopted packages when new packages are needed

## Critical Rules


### Communication Rules

| Rule | Description |
|------|-------------|
| **Concise communication** | Reply in a concise style. Avoid unnecessary repetition or filler |
| **Don't guess** | Don't guess at an answer with low confidence, ask the user |

### Code Quality Rules

| Rule | Description |
|------|-------------|
| **Fix the cause** | No workarounds that only appear to solve the problem |
| **High confidence only** | Only propose solutions you have high confidence in |
| **Package installations** | Always confirm with user before installing new gems or JavaScript packages |

### Rails & ActiveRecord Rules

| Rule | Description |
|------|-------------|
| **Use ActiveRecord methodology** | When rewriting raw SQL statements, use ActiveRecord instead |
| **Use ActiveRecord where/joins** | When encountering raw SQL with joins, rewrite using ActiveRecord join associations and where clauses |
| **Singular database table names** | ActiveRecord models use singular table names, not plural unless stated otherwise |
| **Use Ruby on Rails paradigms** | When creating, modifying, or translating code, use Ruby on Rails paradigms unless this leads to unreadability |
| **Use double quotes** | When creating, modifying, or translating code, use double quoted strings unless it doesn't make sense to do so |
| **Render transient POST results at 422** | Results a GET cannot re-derive (export ledgers, maintenance run results) render their view from the POST with `status: :unprocessable_entity` — Turbo silently drops a 200 form response. Start the view with the scroll-to-top marker (`<div data-controller="scroll-to-top" hidden></div>`); form re-renders with validation errors keep preserved scroll and must not have it. See `design-layouts` |

### Browser Testing Rules

| Rule | Description |
|------|-------------|
| **Browser testing for layout** | Inspect the actual loaded page in browser before making layout changes |
| **Verify browser state** | After resizing browser (desktop/mobile view), confirm the browser is in the desired view before proceeding |
| **Browser automation required** | Use browser automation tooling when inspecting web pages. Abort processing immediately if browser automation cannot be established. Do not continue with any workflow in progress |

### Code Translation Rules

| Rule | Description |
|------|-------------|
| **Assume Laravel 12 when translating PHP code** | When translating Laravel to Ruby on Rails code, assume the code is written using Laravel version 12 and PHP version 8.4. Do not attempt to modify existing ActiveRecord models. Assume any required method will be added later |

## Tech Stack

| Component | Version/Details                                                                          |
|-----------|------------------------------------------------------------------------------------------|
| Ruby on Rails | 8.1                                                                                      |
| Ruby | 4.0                                                                                      |
| Database | MariaDB 10.11                                                                            |
| JavaScript | Stimulus.js, Turbo Frames/Streams; modern ES (class fields, optional chaining), untranspiled via importmap |
| CSS | Tailwind CSS 4, SASS                                                                     |
| UI Library | daisyUI 5 - see the `design-*` skills                                                    |
| Icons | Fontawesome v7.1 free                                                                    |
| Browser | Chrome browser, latest version                                                           |
| IDE | RubyMine                                                                                 |
| Linter | Rubocop                                                                                  |

## Project Structure

| Location | Purpose |
|----------|---------|
| `app/controllers/` | Controllers with different namespaces |
| `app/forms/` | Form objects |
| `app/helpers/` | Custom helpers organized by purpose |
| `app/views/` | View partials with underscores |
| `app/javascript/controllers/` | Stimulus controllers |
| `app/lib/reports/` | Report builders |

## UX/UI Design

For frontend and design work, consult these skills:

- **design-rules**: Approval workflows, critical rules, anti-patterns
- **design-foundations**: Semantic color tokens, typography scale, spacing, dark mode
- **design-components**: Button/card/table/modal helpers and component patterns
- **design-forms**: Form builder patterns, field types, validation
- **design-layouts**: Breakpoints, page patterns, responsive design
- **design-content**: Terminology, ADHD-friendly patterns, accessibility guidelines
- **menus**: Navigation menu system with visibility rules

For comprehensive design documentation, see:
- `docs/DESIGN-GUIDE.md` - Complete design system guide
- `docs/UI-COMPONENTS.md` - Helper method signatures
- `docs/form_helper.md` - Form builder API reference

## Related Skills

- **design-rules** - Critical design rules and approval workflows
- **design-foundations** - Color tokens, typography, spacing
- **design-components** - UI component helpers
- **design-forms** - Form builder patterns
- **design-layouts** - Page layout patterns
- **design-content** - Language rules and accessibility
- **menus** - Navigation menu system
