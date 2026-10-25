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
2. **`swift test` はパッケージルートから実行する。** テストは `URL(fileURLWithPath: "Tests/Resources/...")` という相対パスでフィクスチャを読む（`Bundle.module` ではない）。カレントディレクトリが違うと読み込みに失敗する。
3. **性能リグレッションは PR をブロックする。** `.github/workflows/benchmark.yml` が main をベースラインにして `throughput` p50 の -5% 超の劣化を落とす。`Sources/**` を触ったらローカルでも `swift package benchmark` で確認する。
4. **移植性を壊さない。** CI は macOS / Linux / Windows に加え musl static SDK でもビルドする。プラットフォーム依存 API や Darwin 専用 API は使わない（現状の依存は `Foundation` のみ）。

## API の形 / API shape

- `enum` や `struct` の名前空間を持たず、モジュール `LZString` 直下の**トップレベル public 関数**として公開している（呼び出しは `LZString.compress(input:)` のようにモジュール修飾）。この構造は互換性のために維持する。
- `compress(input:)` は `-> String` と `-> Data` の**戻り値型だけが違うオーバーロード**。呼び出し側は必ず型を明示する:
  ```swift
  let data: Data = LZString.compress(input: text)
  blackHole(LZString.compress(input: text) as Data)
  ```
- 公開 API を追加・変更したら、Base64 / UTF16 / URI / UInt8Array / Data / String の各経路にテストとベンチマークの両方を追加する。

## 実装上の注意 / Implementation notes

- 内部は UTF-16 コードユニット単位で動く（`input.utf16`、`[UInt16]` の辞書キー）。`Character` や `String.Index` 単位に置き換えると絵文字などサロゲートペアで JS との互換性が壊れる。
- `_compress` の本体ループと末尾処理には**意図的に重複した**ビット出力コードがある。オリジナル JS の構造をそのまま写したもので、読みやすさのための安易なリファクタよりも互換性とインライン性能を優先している。
- `keyStrBase64Array` / `keyStrUriSafeArray` は ASCII コードを添字にする 256 要素のルックアップテーブル（性能最適化、commit `8cde82f`）。アルファベットを変えるときは文字列と配列の両方を更新する。
- `_decompress` は UTF-16 LE のバイト列を `Data` に組み立てて最後に `String(data:encoding:.utf16)` で復元する。
- `RollingHash` は辞書探索を高速化するための**作業中の未使用コード**。削除すべきデッドコードとして扱わないこと。

## スタイル / Style

- インデント 4 スペース。テスト名・コメントは日本語で書かれている（既存に合わせる）。英語を併記しているコメントもある。
- テストは **swift-testing**（`import Testing` / `@Suite` / `@Test` / `#expect`）。XCTest は使わない。
- `.gemini/styleguide.md` の方針に従い、このリポジトリでの応答は**英語と日本語の両方**で行う。
