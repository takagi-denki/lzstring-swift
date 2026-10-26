#!/usr/bin/env node
//
// Tests/Resources/js_differential.json を生成する。
// Generates the JS differential fixture used by JavaScriptDifferentialTests.
//
// このスクリプトは `swift test` からは実行されない。フィクスチャはリポジトリに
// コミットされており、通常のテストはネットワークも Node も必要としない。
// Not run by `swift test`. The fixture is committed; normal test runs need neither
// Node nor network access.
//
// 使い方 / Usage:
//   cd Scripts && npm install lz-string@1.5.0 && node generate-js-differential-fixture.js
//
// 辞書ビット幅 (numBits) が増加する位置は、参照実装を**実行時にメモリ上で計装**して
// 特定する。リポジトリ内の参照実装を書き換えることはしない。
// Width transitions are located by instrumenting the reference implementation in memory.

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
  console.error(`参照実装が想定と異なります / reference implementation mismatch:
  version: ${version} (expected ${EXPECTED_VERSION})
  sha256 : ${sha256} (expected ${EXPECTED_SHA256})
固定値を更新する場合は、差分を確認したうえでこのスクリプトの定数も更新してください。`);
  process.exit(1);
}

// numBits の増加箇所に記録フックを挿入した版をメモリ上で読み込む。
// 主ループ側は入力インデックス ii を、末尾処理側は -1 を記録する。
const instrumentedSource = source
  .replace(/(\n\s*)context_numBits\+\+;(\s*\n\s*\})/g, (m, pre, post) => `${pre}context_numBits++; if (globalThis.__lzTrack) globalThis.__lzTrack(typeof ii === "number" ? ii : -1, context_numBits);${post}`);

const instrumented = new Module(refPath, null);
instrumented.filename = refPath;
instrumented.paths = Module._nodeModulePaths(path.dirname(refPath));
instrumented._compile(instrumentedSource, refPath);
const lzInstrumented = instrumented.exports;
const lz = require("lz-string");

// 計装版が本家と同じ出力を出すことを確認する。
for (const probe of ["", "a", "aaa", "hello world", "Lorem ipsum dolor sit amet"]) {
  if (lz.compressToBase64(probe) !== lzInstrumented.compressToBase64(probe)) {
    console.error("計装版の出力が本家と一致しません / instrumented build diverges");
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
  // Swift の String は孤立サロゲートを保持できないため、割れた prefix は採用しない。
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

// 各幅に初到達する位置の 直前 / その位置 / 直後。
// 入力長と辞書サイズは一致しないため、位置は必ず参照実装側の計装で特定する。
for (const baseId of ["repeatedPattern", "jsonLike", "highEntropy"]) {
  const firstAt = {};
  for (const x of transitions(bases[baseId])) if (firstAt[x.nb] === undefined && x.ii >= 0) firstAt[x.nb] = x.ii;

  for (const [nb, ii] of Object.entries(firstAt)) {
    if (Number(nb) < 4) continue; // 幅 3 は入力 1〜3 文字で自明に通過する
    (exercised[baseId] ||= []).push(Number(nb));
    for (const [label, len] of [["before", ii], ["at", ii + 1], ["after", ii + 2]]) {
      if (len < 1 || len > bases[baseId].length) continue;
      const c = expectations(`${baseId}-w${nb}-${label}`, baseId, len,
        `numBits ${nb} への成長${label === "before" ? "直前" : label === "at" ? "時点" : "直後"}`, Number(nb), label);
      if (c) cases.push(c);
    }
  }
}

for (const baseId of Object.keys(bases)) {
  const widths = [...new Set(transitions(bases[baseId]).map(x => x.nb))];
  const c = expectations(`${baseId}-full`, baseId, bases[baseId].length,
    `全長。到達幅 ${JSON.stringify(widths)}`, Math.max(...widths), "full");
  if (c) cases.push(c);
}

const out = { seed: SEED, referenceVersion: version, referenceSha256: sha256, bases, exercised, cases };
const dest = path.join(__dirname, "..", "Tests", "Resources", "js_differential.json");
fs.writeFileSync(dest, JSON.stringify(out, null, 1) + "\n");
console.log(`wrote ${dest}: ${cases.length} cases, widths ${JSON.stringify(exercised)}`);
