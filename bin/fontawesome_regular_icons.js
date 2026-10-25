// Which Font Awesome icons the regular style can draw, as a list IconHelper reads.
//
// Font Awesome Free's regular font carries a glyph for a small part of the
// catalog; the solid font carries nearly all of it. An icon has one codepoint in
// every style, so `fa-regular fa-ban` asks the regular font for a codepoint it
// does not map, the browser falls back past the icon font, and the system's
// last-resort font draws a crossed box. Nothing is logged, and the catalog CSS
// cannot say which names are affected: it declares one `--fa` per icon for all
// styles at once. Only the font's own `cmap` knows.
//
// This reads that `cmap` out of the vendored woff2 and keeps every catalog name
// whose codepoint it maps. IconHelper#fa_icon raises in development and test for
// a regular icon that is not on the list, and test/helpers/icon_helper_test.rb
// checks the raw `fa-regular fa-NAME` class strings fa_icon never sees.
//
// USAGE
//   From the repo root, after a Font Awesome upgrade drops in new fonts and a
//   new all.css (rename CATALOG below, as IconHelper::CATALOG_PATH and the
//   subset task's SOURCE are renamed):
//
//     node bin/fontawesome_regular_icons.js
//
//   The output is generated, never edited by hand. Its header records both
//   sources' SHA-256, and a test fails when either file no longer matches.
//
// WHY NODE
//   A woff2 is one Brotli stream, which Ruby's standard library cannot unpack and
//   Node's zlib can. Node is already needed to build the app's CSS. Standard
//   library only: no package to install.
//
// WHY NOT A RUBY FILE
//   The subset task reads every quoted literal in lib/**/*.rb as an icon name, so
//   a Ruby array of these names would pull all of them into the subset.
//
// WHAT IT DOES NOT READ
//   - A woff2 font collection (flavor `ttcf`). Font Awesome ships none.
//   - Any cmap format but 4 and 12, the two Unicode formats Font Awesome uses.
const crypto = require('crypto');
const fs = require('fs');
const zlib = require('zlib');

const FONT = 'app/assets/webfonts/fa-regular-400.woff2';
const CATALOG = 'lib/fontawesome/fontawesome-7.1.0-all.css';
const OUTPUT = 'lib/fontawesome/regular-icons.txt';

// IconHelper::ICON_BLOCK's twin, also capturing the `--fa` value. Every icon is a
// single-selector block holding one custom property: `.fa-house { --fa: "\f015"; }`
const ICON_BLOCK = /^\.fa-([a-z0-9-]+)\s*\{\s*--fa:\s*"([^"]*)";\s*\}/gm;

// The `--fa` value as a codepoint. A backslash starts a hex escape only when hex
// digits follow it -- `\f015`, or `\30 ` with the one space that ends it.
// Otherwise it escapes the next character, so `\!` is `!` and `\+` is `+`.
// `exclamation`, `plus`, `at` and others are written that way, and read as hex
// they give NaN and silently drop out of the list.
const codepoint = value => {
  const hex = value.match(/^\\([0-9a-fA-F]{1,6}) ?$/);
  if (hex) return parseInt(hex[1], 16);
  return value.replace(/^\\/, '').codePointAt(0);
};

// The woff2 table directory names a table by its index in the spec's list of 63
// known tags, or by an explicit tag after index 63. Only these three matter here:
// cmap is the one read, and glyf and loca are the two whose transform flags mean
// the opposite of every other table's.
const KNOWN_TAGS = { 0: 'cmap', 10: 'glyf', 11: 'loca' };

// The decompressed cmap table of a woff2 font.
const cmapTable = woff2 => {
  if (woff2.toString('latin1', 0, 4) !== 'wOF2') throw new Error(`${FONT} is not a woff2 font`);
  const numTables = woff2.readUInt16BE(12);
  const compressedLength = woff2.readUInt32BE(20);

  let pos = 48;   // the fixed-size header
  const base128 = () => {
    let value = 0;
    for (let i = 0; i < 5; i++) {
      const byte = woff2[pos++];
      value = value * 128 + (byte & 0x7f);
      if (!(byte & 0x80)) return value;
    }
    throw new Error('bad UIntBase128');
  };

  // Every table is stored back to back in one Brotli stream, in directory order
  // and without padding, each at its transformed length when it has one.
  let offset = 0;
  let cmap = null;
  for (let i = 0; i < numTables; i++) {
    const flags = woff2[pos++];
    const index = flags & 0x3f;
    const tag = index === 63 ? woff2.toString('latin1', pos, (pos += 4)) : KNOWN_TAGS[index];
    const version = flags >> 6;
    const length = base128();
    const transformed = tag === 'glyf' || tag === 'loca' ? version !== 3 : version !== 0;
    const stored = transformed ? base128() : length;
    if (tag === 'cmap') cmap = { offset, length: stored };
    offset += stored;
  }
  if (!cmap) throw new Error(`${FONT} has no cmap table`);

  const tables = zlib.brotliDecompressSync(woff2.subarray(pos, pos + compressedLength));
  return tables.subarray(cmap.offset, cmap.offset + cmap.length);
};

// Every codepoint the cmap maps to a real glyph (glyph 0 is .notdef, the box).
const mappedCodepoints = cmap => {
  const mapped = new Set();
  const numSubtables = cmap.readUInt16BE(2);
  for (let i = 0; i < numSubtables; i++) {
    const at = cmap.readUInt32BE(4 + i * 8 + 4);
    const format = cmap.readUInt16BE(at);

    if (format === 4) {
      const segments = cmap.readUInt16BE(at + 6) / 2;
      const ends = at + 14;
      const starts = ends + segments * 2 + 2;
      const deltas = starts + segments * 2;
      const rangeOffsets = deltas + segments * 2;
      for (let s = 0; s < segments; s++) {
        const start = cmap.readUInt16BE(starts + s * 2);
        const end = cmap.readUInt16BE(ends + s * 2);
        const delta = cmap.readUInt16BE(deltas + s * 2);
        const rangeAt = rangeOffsets + s * 2;
        const rangeOffset = cmap.readUInt16BE(rangeAt);
        for (let c = start; c <= end && c !== 0xffff; c++) {
          let glyph = rangeOffset === 0 ? c : cmap.readUInt16BE(rangeAt + rangeOffset + (c - start) * 2);
          if (rangeOffset === 0 || glyph !== 0) glyph = (glyph + delta) & 0xffff;
          if (glyph !== 0) mapped.add(c);
        }
      }
    } else if (format === 12) {
      const groups = cmap.readUInt32BE(at + 12);
      for (let g = 0; g < groups; g++) {
        const group = at + 16 + g * 12;
        const start = cmap.readUInt32BE(group);
        const end = cmap.readUInt32BE(group + 4);
        const firstGlyph = cmap.readUInt32BE(group + 8);
        for (let c = start; c <= end; c++) {
          if (firstGlyph + (c - start) !== 0) mapped.add(c);
        }
      }
    }
  }
  return mapped;
};

const font = fs.readFileSync(FONT);
const catalog = fs.readFileSync(CATALOG);
const mapped = mappedCodepoints(cmapTable(font));

// Four brand names are declared twice, at one codepoint each time.
const icons = new Map();
for (const [, name, value] of catalog.toString('utf8').matchAll(ICON_BLOCK)) icons.set(name, codepoint(value));
const kept = [...icons].filter(([, cp]) => mapped.has(cp)).map(([name]) => name).sort();

const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
fs.writeFileSync(OUTPUT, [
  '# GENERATED -- do not edit. Run `node bin/fontawesome_regular_icons.js` to rebuild.',
  '#',
  `# The ${kept.length} of the catalog's ${icons.size} icon names whose codepoint the regular font`,
  '# maps: the only names the regular style draws. Any other draws a crossed box.',
  '#',
  `# Glyphs: ${FONT} sha256 ${sha256(font)}`,
  `# Names:  ${CATALOG} sha256 ${sha256(catalog)}`,
  ...kept,
  ''
].join('\n'));

console.log(`Kept ${kept.length} of ${icons.size} icons.`);
