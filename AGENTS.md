# AGENTS.md

lz-string（[pieroxy/lz-string](https://github.com/pieroxy/lz-string)）の Swift 移植ライブラリ。

## コマンド / Commands

```sh
swift build --target LZString          # ライブラリのみビルド（CI と同じ）
swift test                             # 必ずパッケージルートで実行（後述）
swift package benchmark                # ベンチマーク実行（要 jemalloc）
swift package --allow-writing-to-package-directory benchmark baseline update <name>
swift package --allow-writing-to-package-directory benchmark baseline check <name>
```

- Swift 6.2 / swift-tools-version:6.2。対応プラットフォームは macOS 13+, iOS 13+, tvOS 13+, watchOS 6+。
- ベンチマークには `libjemalloc` が必要（Linux: `apt-get install -y libjemalloc-dev`、macOS: `brew install jemalloc`）。

## 構成 / Layout

| パス | 役割 |
| --- | --- |
| `Sources/LZString/LZString.swift` | 実装のすべて（単一ファイル） |
| `Tests/LZStringTests/LZStringTests.swift` | swift-testing によるテスト |
| `Tests/Resources/*.txt` | JS 版の出力と一致することを保証する**ゴールデンファイル** |
| `Benchmarks/LZStringBenchmarks/` | ordo-one/package-benchmark によるベンチ |

## 絶対に守ること / Hard rules

1. **JS 版とのバイト単位の互換性が最優先。** `Tests/Resources/` の固定値はオリジナルの JavaScript 実装が生成した出力。テストが落ちたときに**フィクスチャを作り直して通してはいけない** — 落ちているのは実装側のリグレッション。
   - 互換性は**空入力にも及ぶ**。JS 版は空文字列と null を区別し、空文字列に対しても終端コードを出力する。圧縮関数で空入力を早期 return してはいけない（issue #33）。往復テストだけでは検出できないため、各形式の出力を JS の固定値と直接突き合わせる。
   - 展開 API の空入力は空文字列を返す（JS は null だが Swift の戻り値型は `String`）。これは圧縮側とは別の規約。
   - `Tests/Resources/js_differential.json` は辞書ビット幅の成長境界を狙った JS 差分コーパス（issue #41）。参照実装のバージョンと sha256、入力生成の seed を内部に記録している。再生成は `Scripts/generate-js-differential-fixture.js`（Node が必要）で、`swift test` からは実行されない。**テストが落ちたときに再生成して通してはいけない。**
2. **`swift test` はパッケージルートから実行する。** テストは `URL(fileURLWithPath: "Tests/Resources/...")` という相対パスでフィクスチャを読む（`Bundle.module` ではない）。カレントディレクトリが違うと読み込みに失敗する。
3. **性能リグレッションは PR をブロックする。** `.github/workflows/benchmark.yml` が PR の base コミットをベースラインにして、`throughput` p50 が **15% 超**低下した場合に落とす。`Sources/**` を触ったらローカルでも `swift package benchmark` で確認する。
   - 閾値が 15% なのは測定の都合による（issue #56）。throughput のパーセンタイルは K 単位に正規化された整数として保存されるため、保存値 23K なら 1 単位が 4.3%、2 単位で 8.7% に相当する。**5% ではコードを変えなくても 3 回中 2 回失敗した**ため、偽陽性を無くせる水準まで上げてある。閾値を下げたい場合は、先に測定の分解能を上げること。
   - 判定対象は `throughput` p50 のみ。壁時計時間・malloc・メモリは記録するが判定しない（同一コードでメモリが 40% 振れた実績がある）。
4. **移植性を壊さない。** CI は macOS / Linux / Windows に加え musl static SDK でもビルドする。プラットフォーム依存 API や Darwin 専用 API は使わない（現状の依存は `Foundation` のみ）。

## API の形 / API shape

- `enum` や `struct` の名前空間を持たず、モジュール `LZString` 直下の**トップレベル public 関数**として公開している（呼び出しは `LZString.compress(input:)` のようにモジュール修飾）。この構造は互換性のために維持する。
- `compress(input:)` は `-> String` と `-> Data` の**戻り値型だけが違うオーバーロード**。呼び出し側は必ず型を明示する:
  ```swift
  let data: Data = LZString.compress(input: text)
  blackHole(LZString.compress(input: text) as Data)
  ```
- 生の `String` 形式（`compress(input:) -> String` と `decompress(input: String)`）は**非推奨**。生の 16 ビットストリームには対になっていないサロゲートが現れることがあり、Swift の `String` はそれを表現できず `U+FFFD` に置換されるため不可逆（issue #22）。可逆な形式は `Data` / `[UInt8]` / `compressToUTF16`。
  - パッケージ内でこの形式を意図的に使っている箇所（テストとベンチマーク）は、囲む宣言に `@available(*, deprecated)` を付けて警告を抑えている。Swift には警告抑制のプラグマがないため、ベンチマークの呼び出し 1 箇所だけは警告が残る（意図的）。
- 公開 API を追加・変更したら、Base64 / UTF16 / URI / UInt8Array / Data / String の各経路にテストとベンチマークの両方を追加する。

## 実装上の注意 / Implementation notes

- 内部は UTF-16 コードユニット単位で動く（`input.utf16`、`[UInt16]` の辞書キー）。`Character` や `String.Index` 単位に置き換えると絵文字などサロゲートペアで JS との互換性が壊れる。
- `_compress` の本体ループと末尾処理には**意図的に重複した**ビット出力コードがある。オリジナル JS の構造をそのまま写したもので、読みやすさのための安易なリファクタよりも互換性とインライン性能を優先している。
- `keyStrBase64Array` / `keyStrUriSafeArray` は ASCII コードを添字にする 256 要素のルックアップテーブル（性能最適化、commit `8cde82f`）。アルファベットを変えるときは文字列と配列の両方を更新する。
- `_decompress` は復号結果を UTF-16 コードユニット (`[UInt16]`) のまま貯め、最後に `String(decoding:as: UTF16.self)` で復元する。バイト列に落として `String(data:encoding:.utf16)` に渡してはいけない — 先頭の U+FEFF / U+FFFE が BOM として解釈され、文字が失われる（issue #23）。

## スタイル / Style

- インデント 4 スペース。テスト名・コメントは日本語で書かれている（既存に合わせる）。英語を併記しているコメントもある。
- テストは **swift-testing**（`import Testing` / `@Suite` / `@Test` / `#expect`）。XCTest は使わない。
- Issue・PR・レビューコメントなどのコミュニケーションは、日本語と英語を併記してよい（必須ではない）。
