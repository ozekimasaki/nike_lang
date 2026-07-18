# AGENTS.md

このリポジトリで作業するコーディングエージェント向けのガイドです。NIKE language は Brainfuck 風のミニ言語で、その処理系（CLI・インタプリタ・C バックエンド）を Zig で実装しています。

## プロジェクト構成 / エントリポイント

```
.
├── build.zig            # Zig ビルド定義（exe / run / test ステップ）
├── src/
│   ├── main.zig         # CLI エントリポイント。引数解析と各コマンドの振り分け
│   ├── lang.zig         # 字句解析・構文解析・診断・spec 出力（compileSource, writeSpec）
│   ├── ir.zig           # Instruction 列挙型と Program 構造体
│   ├── runner.zig       # インタプリタ(execute) と zig cc 呼び出し(compileCToNative)
│   ├── c_backend.zig    # IR から C ソースを生成(emitSource)
│   └── all_tests.zig    # `zig build test` のテストエントリ（各モジュールを取り込む）
└── examples/            # サンプル NIKE プログラム（hello.nike, echo.nike）
```

- 実行ファイル名は `nike`（`build.zig` の `exe.name`）。ルートソースは `src/main.zig`。
- CLI コマンドは `spec` / `run` / `compile` / `help`。`main.zig` の `runCli` が起点。
- 言語のパイプラインは「`lang.compileSource`（ソース→IR + 診断）→ `runner.execute`（実行）または `c_backend.emitSource`（C 生成）→ `runner.compileCToNative`（ネイティブ化）」。

## セットアップ

- [Zig](https://ziglang.org/) を用意します。`build.zig` は Zig 0.14 系の Build API（`b.createModule` / `root_module` など）を使っています。
- ネイティブコンパイル（`nike compile -o`）は `zig cc` を内部で呼ぶため、Zig 以外の C コンパイラは不要です。
- 追加の外部依存やパッケージマネージャ設定（`build.zig.zon` 等）はありません。

## ビルド / テスト / lint / typecheck コマンド

実在するコマンドは Zig の標準ビルドコマンドのみです。

```sh
zig build                 # ビルドして zig-out/bin/nike を生成
zig build test            # 全テストを実行（all_tests.zig 経由）
zig build run -- <args>   # ビルドして nike に <args> を渡して実行
```

例:

```sh
zig build run -- spec
zig build run -- run examples/hello.nike
```

- **テスト**: `zig build test`。テストは `src/*.zig` 内の `test { ... }` ブロックに書かれ、`src/all_tests.zig` が各モジュールを参照して集約します。新しいテストは対応するモジュールの `test` ブロックとして追加してください。
- **lint / typecheck 専用コマンド**: 独立した lint / typecheck ツールの設定はありません。型検査はコンパイル時に行われるため、`zig build` と `zig build test` がその役割を兼ねます。
- **フォーマット**: 標準の `zig fmt` が利用できます（例: `zig fmt src/`）。CI 設定は存在しないため、変更後は手元で `zig build test` を実行して確認してください。

## コーディング規約

- Zig 標準のスタイルに従います。インデントは 4 スペース、フォーマットは `zig fmt` に準拠。
- 命名は既存コードに合わせる: 関数・変数は `lowerCamelCase`、型・列挙型は `UpperCamelCase`、列挙タグは `snake_case`（例: `move_right`, `loop_start`）。
- エラーは Zig のエラー共用体で表現し、CLI 層（`main.zig`）でユーザ向けメッセージへ変換します（`runner.RunnerError`, `lang.Diagnostic` を参照）。パニックではなくエラー返却を優先。
- メモリはアロケータを明示的に受け渡し、確保したものは `defer` / `deinit` で解放します（`Program.deinit`, `ArrayList.deinit` などのパターンに倣う）。
- 診断メッセージは `nike parse error ...` / `nike runtime error ...` / `nike compile error ...` の既存フォーマットに合わせます。

## 注意点

- 言語のキーワードは日本語（`AIニケ`, `ニケ`, `ブヒ夫`, `ぷにけ`, `ノルカス`, `ミカゼ`）で、ソースは UTF-8 前提です。文字列を編集する際はエンコーディングを壊さないこと。
- 命令は必ず 2 単語 1 組。命令の追加・変更時は `lang.identifyWord` / `lang.mapPair`、`ir.Instruction`、`runner.execute`、`c_backend.emitSource`、`lang.writeSpec` の整合を取り、README の命令対応表も更新してください。
- インタプリタ（`runner.execute`）と C バックエンド（`c_backend.emitSource`）は同じ IR を消費するため、セマンティクス（8-bit ラップ、テープ拡張、EOF→0、左方向アンダーフローのエラー）を両者で一致させること。
- `main.zig` は Windows でコンソール出力を UTF-8（CP 65001）に設定します。プラットフォーム依存の挙動を変更する場合は注意。
- `.gitignore` により `.zig-cache/`, `zig-out/`, `*.exe`, `*.obj`, `*.pdb` は追跡対象外です。ビルド成果物をコミットしないこと。
- CI / pre-commit フックは設定されていません。変更後は必ずローカルで `zig build test` を通してください。
