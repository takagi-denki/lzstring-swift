#!/usr/bin/env node
//
// Generates Tests/Resources/js_differential.json, the differential fixture used by
// JavaScriptDifferentialTests.
//
// Not run by `swift test`. The fixture is committed; normal test runs need neither
// Node nor network access.
//
// Usage:
//   cd Scripts && npm install lz-string@1.5.0 && node generate-js-differential-fixture.js
//
// Width transitions are located by instrumenting the reference implementation in memory
// at run time; nothing in the repository's copy of it is modified.

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const Module = require("module");

const SEED = 20261026;
const EXPECTED_VERSION = "1.5.0";
const EXPECTED_SHA256 = "550034b821027008776cb9bcd1700bb5d31e8b3de224cb130fc966a75dab0e5e";

const refPath = require.resolve("lz-string/libs/lz-string.js");
const source = fs.readFileSync(refPath, "utf8");
const sha256 = crypto.createHash("sha256").update(fs.readFileSync(refPath)).digest("hex");
const version = require("lz-string/package.json").version;

if (version !== EXPECTED_VERSION || sha256 !== EXPECTED_SHA256) {
  console.error(`Reference implementation mismatch:
  version: ${version} (expected ${EXPECTED_VERSION})
  sha256 : ${sha256} (expected ${EXPECTED_SHA256})
To update the pinned values, review the difference and update the constants above.`);
  process.exit(1);
}

// Load an in-memory copy with a recording hook inserted where numBits grows. The main
// loop records the input index ii; the tail handling records -1.
const instrumentedSource = source
  .replace(/(\n\s*)context_numBits\+\+;(\s*\n\s*\})/g, (m, pre, post) => `${pre}context_numBits++; if (globalThis.__lzTrack) globalThis.__lzTrack(typeof ii === "number" ? ii : -1, context_numBits);${post}`);

const instrumented = new Module(refPath, null);
instrumented.filename = refPath;
instrumented.paths = Module._nodeModulePaths(path.dirname(refPath));
instrumented._compile(instrumentedSource, refPath);
const lzInstrumented = instrumented.exports;
const lz = require("lz-string");

// Confirm the instrumented build produces the same output as the original.
for (const probe of ["", "a", "aaa", "hello world", "Lorem ipsum dolor sit amet"]) {
  if (lz.compressToBase64(probe) !== lzInstrumented.compressToBase64(probe)) {
    console.error("Instrumented build diverges from the original");
    process.exit(1);
  }
}

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    var t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

const rnd = mulberry32(SEED);
const highEntropy = (() => { let s = ""; for (let i = 0; i < 1800; i++) s += String.fromCharCode(32 + Math.floor(rnd() * 95)); return s; })();

const bases = {
  repeatedPattern: "abcabcabd".repeat(40),
  jsonLike: JSON.stringify({ users: [...Array(40)].map((_, i) => ({ id: i, name: "user" + i, active: i % 2 === 0, tags: ["a", "b"] })) }),
  highEntropy,
  asciiProse: "the quick brown fox jumps over the lazy dog. ".repeat(12),
  mixedScripts: (() => { let s = ""; const parts = ["abc", "日本語", "ĄČĘ", "🥺", "αβγ", "한글"]; for (let i = 0; i < 70; i++) s += parts[i % parts.length]; return s; })(),
};

function transitions(s) {
  const t = [];
  globalThis.__lzTrack = (ii, nb) => t.push({ ii, nb });
  lzInstrumented.compressToBase64(s);
  globalThis.__lzTrack = null;
  return t;
}

const hex = a => a.map(x => x.toString(16).padStart(2, "0")).join("");
const hex16 = a => a.map(x => x.toString(16).padStart(4, "0")).join("");
const units = s => { const a = []; for (let i = 0; i < s.length; i++) a.push(s.charCodeAt(i)); return a; };
const hasLoneSurrogate = s => {
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) { const n = s.charCodeAt(i + 1); if (!(n >= 0xDC00 && n <= 0xDFFF)) return true; i++; }
    else if (c >= 0xDC00 && c <= 0xDFFF) return true;
  }
  return false;
};

function expectations(id, baseId, prefixLength, note, width, position) {
  const s = bases[baseId].slice(0, prefixLength);
  // A Swift String cannot hold a lone surrogate, so a prefix that splits a pair is skipped.
  if (hasLoneSurrogate(s)) return null;
  if (lz.decompressFromBase64(lz.compressToBase64(s)) !== s) throw new Error("js roundtrip failed: " + id);
  return {
    id, baseId, prefixLength, note, width, position,
    base64: lz.compressToBase64(s),
    uri: lz.compressToEncodedURIComponent(s),
    utf16Hex: hex16(units(lz.compressToUTF16(s))),
    uint8Hex: hex(Array.from(lz.compressToUint8Array(s))),
    inputUtf16Hex: hex16(units(s)),
  };
}

const cases = [];
const exercised = {};

// The position just before, at, and just after the first time each width is reached.
// Input length and dictionary size do not correspond, so positions always come from the
// instrumented reference implementation.
for (const baseId of ["repeatedPattern", "jsonLike", "highEntropy"]) {
  const firstAt = {};
  for (const x of transitions(bases[baseId])) if (firstAt[x.nb] === undefined && x.ii >= 0) firstAt[x.nb] = x.ii;

  for (const [nb, ii] of Object.entries(firstAt)) {
    if (Number(nb) < 4) continue; // Width 3 is reached trivially within the first few characters.
    (exercised[baseId] ||= []).push(Number(nb));
    for (const [label, len] of [["before", ii], ["at", ii + 1], ["after", ii + 2]]) {
      if (len < 1 || len > bases[baseId].length) continue;
      const c = expectations(`${baseId}-w${nb}-${label}`, baseId, len,
        `growth to numBits ${nb}, ${label}`, Number(nb), label);
      if (c) cases.push(c);
    }
  }
}

for (const baseId of Object.keys(bases)) {
  const widths = [...new Set(transitions(bases[baseId]).map(x => x.nb))];
  const c = expectations(`${baseId}-full`, baseId, bases[baseId].length,
    `full length; widths reached ${JSON.stringify(widths)}`, Math.max(...widths), "full");
  if (c) cases.push(c);
}

const out = { seed: SEED, referenceVersion: version, referenceSha256: sha256, bases, exercised, cases };
const dest = path.join(__dirname, "..", "Tests", "Resources", "js_differential.json");
fs.writeFileSync(dest, JSON.stringify(out, null, 1) + "\n");
console.log(`wrote ${dest}: ${cases.length} cases, widths ${JSON.stringify(exercised)}`);

// --- Large repeated phrases (issue #34) -----------------------------------------------
// The corpus above is built from prefixes of three roughly 2 KiB bases, so the phrases it
// reaches stay short. The compressor identifies a phrase by its prefix's dictionary code,
// which only diverges from the original phrase-keyed lookup once phrases grow long and the
// dictionary deepens, so these cases go up to 1 Mi UTF-16 units.
//
// Repeated input is what makes that affordable: 1 Mi units of "a" compress to about 2.3 KiB
// of Base64, so the expectations can be committed in full rather than hashed. The input
// itself is not committed; both sides build it from `unit` and `count`.
const repeatedSpecs = [
  { id: "a-4Ki",       unit: "a",    count: 4096,   note: "single character, 4 Ki units" },
  { id: "a-16Ki",      unit: "a",    count: 16384,  note: "single character, 16 Ki units" },
  { id: "a-64Ki",      unit: "a",    count: 65536,  note: "single character, 64 Ki units" },
  { id: "a-256Ki",     unit: "a",    count: 262144, note: "single character, 256 Ki units" },
  { id: "a-1Mi",       unit: "a",    count: 1048576, note: "single character, 1 Mi units" },
  { id: "ab-8Ki",      unit: "ab",   count: 4096,   note: "two-character pattern, 8 Ki units" },
  { id: "abcd-1Mi",    unit: "abcd", count: 262144, note: "four-character pattern, 1 Mi units" },
  { id: "japanese-64Ki", unit: "\u65e5\u672c", count: 32768, note: "non-ASCII BMP pattern, 64 Ki units" },
  // Surrogate pairs: a phrase boundary can fall between the two halves of one emoji.
  { id: "emoji-64Ki",  unit: "\u{1F600}", count: 32768, note: "surrogate pairs, 64 Ki units" },
];

const repeated = repeatedSpecs.map(spec => {
  const s = spec.unit.repeat(spec.count);
  if (lz.decompressFromBase64(lz.compressToBase64(s)) !== s) throw new Error("js roundtrip failed: " + spec.id);
  return {
    ...spec,
    inputUtf16Units: s.length,
    base64: lz.compressToBase64(s),
    uri: lz.compressToEncodedURIComponent(s),
    utf16Hex: hex16(units(lz.compressToUTF16(s))),
    uint8Hex: hex(Array.from(lz.compressToUint8Array(s))),
  };
});

const largeOut = { referenceVersion: version, referenceSha256: sha256, cases: repeated };
const largeDest = path.join(__dirname, "..", "Tests", "Resources", "js_large_phrases.json");
fs.writeFileSync(largeDest, JSON.stringify(largeOut, null, 1) + "\n");
console.log(`wrote ${largeDest}: ${repeated.length} cases, ` +
  `${repeated.reduce((a, b) => a + b.inputUtf16Units, 0).toLocaleString()} input UTF-16 units`);
