# Clubhouse 3 Core Standards

## Critical Rules

## Tech Stack

| Component | Version |
|-----------|---------|
| Ruby on Rails | 8.1 |
| Ruby | 4.0 |
| Database | MariaDB 10.11 |
| JavaScript | Stimulus.js, Turbo Frames/Streams; modern ES, untranspiled via importmap |
| CSS | Tailwind CSS 4, SASS |
| UI Library | daisyUI 5 |
| Icons | FontAwesome v7.1 free |

## Critical Rules

### Code Quality
- **Fix the cause** - No workarounds that only appear to solve the problem
- **High confidence only** - Only propose solutions with high confidence
- **Package installations** - Confirm with user before installing new gems or JS packages

### Rails & ActiveRecord
- Use ActiveRecord instead of raw SQL
- Use ActiveRecord joins/where instead of raw SQL joins
- Singular database table names (not plural)
- Use double quoted strings
- Follow Ruby on Rails paradigms

### Browser Testing
- Inspect actual loaded page before layout changes
- Browser automation required - abort if unavailable

## Development Philosophy

Prioritize: economy of motion, surgical precision, no unnecessary changes, use existing packages.
