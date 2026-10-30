# AGENTS.md

A Swift port of lz-string ([pieroxy/lz-string](https://github.com/pieroxy/lz-string)).

## Commands

```sh
swift build --target LZString          # build the library only (what CI does)
swift test                             # must be run from the package root (see below)
swift package benchmark                # run the benchmarks (requires jemalloc)
swift package --allow-writing-to-package-directory benchmark baseline update <name>
swift package --allow-writing-to-package-directory benchmark baseline check <name>
```

- Swift 6.2 / swift-tools-version:6.2. Supported platforms are macOS 13+, iOS 13+, tvOS 13+, watchOS 6+.
- The benchmarks need `libjemalloc` (Linux: `apt-get install -y libjemalloc-dev`, macOS: `brew install jemalloc`).

## Layout

| Path | Role |
| --- | --- |
| `Sources/LZString/LZString.swift` | The entire implementation (a single file) |
| `Tests/LZStringTests/LZStringTests.swift` | Tests, written with swift-testing |
| `Tests/Resources/*.txt` | **Golden files** that pin agreement with the JavaScript implementation |
| `Benchmarks/LZStringBenchmarks/` | Benchmarks, using ordo-one/package-benchmark |

## Hard rules

1. **Byte-for-byte compatibility with the JavaScript implementation comes first.** The fixed values under `Tests/Resources/` are output produced by the original JavaScript implementation. When a test fails, **do not regenerate the fixtures to make it pass** — the failure is a regression in the implementation.
   - Compatibility **extends to empty input**. The JavaScript implementation distinguishes an empty string from null and still emits the end-of-stream code for an empty string. Compressors must not return early for empty input (issue #33). A round-trip test cannot detect this, so each format's output is compared against the fixed JavaScript value directly.
   - Decompression APIs return an empty string for empty input (JavaScript returns null, but the Swift return type is `String`). This is a separate contract from the compression side.
   - `Tests/Resources/js_differential.json` is a differential corpus aimed at dictionary bit-width transitions (issue #41). It records the reference implementation's version and sha256, and the input-generation seed. Regenerate it with `Scripts/generate-js-differential-fixture.js` (needs Node); `swift test` never runs it. **Do not regenerate it to make a failing test pass.**
2. **Run `swift test` from the package root.** The tests read fixtures through paths relative to the working directory (`URL(fileURLWithPath: "Tests/Resources/...")`, not `Bundle.module`), so they fail to load from anywhere else.
3. **Allocation regressions block a PR.** `.github/workflows/benchmark.yml` takes the PR's base commit as the baseline and fails when `mallocCountTotal` p50 grows by more than **25%, or by more than 50 allocations**. Run `swift package benchmark` locally whenever you touch `Sources/**`, and report throughput there — CI does not check it.
   - **The gate is on the malloc count because it is the only deterministic metric here.** Identical code allocates an identical number of times, so the gate cannot fire on measurement noise. Both a relative and an absolute tolerance are set, and package-benchmark evaluates them independently, so either one firing is a deviation. The relative tolerance catches an algorithmic regression, which shows up as a multiple rather than a few percent. The absolute tolerance covers the case the relative one cannot, where the baseline count is 0 and package-benchmark reports a relative difference of 0 to avoid dividing by zero.
   - **Throughput is not gated** (issue #87). The workflow measures the baseline and the candidate sequentially in one job, and the second measurement is systematically lower: a commit that only added a comment, compiling to code identical to `main`, was reported as 18–29% worse on 9 of 18 benchmarks. No tolerance that still catches a real regression survives a bias that large. This is a different problem from the quantisation in #56 — it appeared at a stored value of 7279, where one unit is 0.014%.
   - Wall clock, throughput and memory are recorded but not checked. Allocated resident memory is not attributable at all: it has moved by 40% for identical code, and it moves on benchmarks whose code a change did not touch.
   - **What this does not catch:** a regression that costs time without allocating. If you make one deliberately, say so in the pull request; the measurement to trust is a local `swift package benchmark` comparison.
4. **Do not break portability.** CI builds on macOS, Linux and Windows, plus the musl static SDK. Do not use platform-specific or Darwin-only APIs (the only dependency today is `Foundation`).

## API shape

- The API has no `enum` or `struct` namespace: it is exposed as **top-level public functions** in the `LZString` module, so call sites qualify them by module, as in `LZString.compress(input:)`. Keep this structure for compatibility.
- `compress(input:)` is **overloaded on its return type** (`-> String` and `-> Data`), so call sites must state the type:
  ```swift
  let data: Data = LZString.compress(input: text)
  blackHole(LZString.compress(input: text) as Data)
  ```
- The raw `String` format (`compress(input:) -> String` and `decompress(input: String)`) is **deprecated**. The raw 16-bit stream can contain unpaired surrogates, which a Swift `String` cannot represent and replaces with `U+FFFD`, making the format lossy (issue #22). The lossless formats are `Data`, `[UInt8]` and `compressToUTF16`.
  - Where the package uses this format deliberately (tests and benchmarks), the enclosing declaration is marked `@available(*, deprecated)` to silence the warning. Swift has no pragma for suppressing warnings, so one call site in the benchmarks still warns; that is intentional.
- When you add or change a public API, add both tests and benchmarks for every path: Base64, UTF16, URI, UInt8Array, Data and String.

## Implementation notes

- The internals work in UTF-16 code units (`input.utf16`, dictionary keys of `[UInt16]`). Switching to `Character` or `String.Index` units breaks compatibility with JavaScript for surrogate pairs such as emoji.
- The main loop and the tail handling of `_compress` contain **deliberately duplicated** bit-output code. It mirrors the structure of the original JavaScript, and compatibility and inlining are preferred over a readability refactor.
- `keyStrBase64Array` and `keyStrUriSafeArray` are 256-element lookup tables indexed by ASCII code (a performance optimisation, commit `8cde82f`). When changing an alphabet, update both the string and the array.
  - The encoding side uses `keyStrBase64Bytes` / `keyStrUriSafeBytes`, which are **derived** from the alphabet strings with `Array(keyStrBase64.utf8)` (issue #77). Do not write them out as literals: deriving them is what keeps them from drifting away from the strings.
- `_decompress` accumulates the decoded result as UTF-16 code units (`[UInt16]`) and builds the string with `String(decoding:as: UTF16.self)`. Do not serialise it to bytes and pass it to `String(data:encoding:.utf16)` — a leading U+FEFF or U+FFFE is then read as a BOM and the character is lost (issue #23).

## Style

- Four-space indentation.
- Tests use **swift-testing** (`import Testing` / `@Suite` / `@Test` / `#expect`). Do not use XCTest.

### Language

- **Write code-facing text in English.** This covers identifiers, comments, documentation comments, `@Suite` and `@Test` display names, test function names, assertion descriptions, and developer-facing or diagnostic messages across `Sources`, `Tests`, `Benchmarks` and `Scripts`.
- It also covers the CI workflows under `.github/` and the repository-level configuration they rely on, such as `Package.swift` and `codecov.yml`: comments there explain why a job, a platform exclusion or a threshold is set the way it is, and are read in the same way as code.
- Documentation comments on public APIs are English only. Keep the existing warnings on the deprecated APIs, in English.
- The policy applies to new and changed code. Parts of the existing code are still written in Japanese; translating the repository wholesale is a separate task and is not required here.
- **Do not translate or remove multilingual test data.** Japanese text, emoji and combining characters used as test input or expected values exist to verify Unicode compatibility. Golden files and reference data stay as they are.
- Do not change strings or public identifiers that an external specification or API compatibility depends on, merely for language consistency.
- GitHub issue and pull request descriptions, discussion comments and review comments may be written in Japanese, in English, or in both. Bilingual communication is permitted, not required.
- This policy governs text in the repository, not the language used when talking to the person you are working with, and it does not deprecate Japanese documentation such as `README.ja.md`.
