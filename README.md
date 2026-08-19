# NIKE language

Brainfuck 風のミニ言語と、その処理系（インタプリタ + C バックエンド）です。Zig 製の CLI `nike` から、ソースの実行・仕様表示・ネイティブ実行ファイルへのコンパイルが行えます。

ソースコードで使える単語は次の6語だけです。

- `AIニケ`
- `ニケ`
- `ブヒ夫`
- `ぷにけ`
- `ノルカス`
- `ミカゼ`

## 主な機能

- **インタプリタ実行**: `nike run` で NIKE ソースをその場で解釈実行します。
- **仕様表示**: `nike spec` で言語仕様と命令対応表を出力します。
- **C へのコンパイル**: NIKE ソースを C ソースへ変換します（`--emit-c`）。
- **ネイティブコンパイル**: 生成した C を `zig cc` でネイティブ実行ファイルにビルドします（`-o`）。
- **詳細な診断メッセージ**: 未知の単語・単語数の不一致・不正なペア・ループの対応漏れなどを、単語位置とバイト範囲付きで報告します。

## v1 仕様

- ソースは UTF-8（先頭の BOM は許容され、無視されます）
- 空白は区切りとしてのみ使う
- 命令は **必ず2単語1組**
- v1 ではコメント非対応
- セルは 8-bit、加減算はラップアラウンド
- テープは右方向へ必要に応じて拡張（インタプリタは初期 1024 セル）
- 左へ 0 未満に動くと実行時エラー
- 入力 EOF は `0` を書き込む

## 命令対応表

| NIKE | Brainfuck | 意味 |
| --- | --- | --- |
| `AIニケ ニケ` | `>` | ポインタを右へ |
| `ニケ AIニケ` | `<` | ポインタを左へ |
| `ブヒ夫 ぷにけ` | `+` | 現在セルを加算 |
| `ぷにけ ブヒ夫` | `-` | 現在セルを減算 |
| `ノルカス ミカゼ` | `.` | 1バイト出力 |
| `ミカゼ ノルカス` | `,` | 1バイト入力 |
| `AIニケ ブヒ夫` | `[` | ループ開始 |
| `ブヒ夫 AIニケ` | `]` | ループ終了 |

## 要件

- [Zig](https://ziglang.org/)（`build.zig` は Zig 0.14 系の Build API を使用しています）
- ネイティブ実行ファイルを生成する場合のみ `zig cc` を使うため、Zig があれば追加の C コンパイラは不要です。

## インストール / ビルド

リポジトリを取得して Zig でビルドします。

```sh
git clone https://github.com/ozekimasaki/nike_lang.git
cd nike_lang
zig build
```

ビルドすると `zig-out/bin/nike`（Windows では `zig-out\bin\nike.exe`）が生成されます。

## 使い方

CLI（PowerShell / Windows の例）:

```powershell
zig-out\bin\nike spec
zig-out\bin\nike run examples\hello.nike
zig-out\bin\nike run examples\echo.nike
zig-out\bin\nike compile examples\echo.nike --emit-c echo.c
zig-out\bin\nike compile examples\echo.nike -o echo.exe
zig-out\bin\nike compile examples\echo.nike -o echo.exe --zig C:\path\to\zig.exe
```

macOS / Linux では `zig-out/bin/nike` を使います。

```sh
zig-out/bin/nike run examples/hello.nike
```

ビルドせずに `zig build run` から直接実行することもできます（`--` の後ろが `nike` への引数です）。

```sh
zig build run -- run examples/hello.nike
zig build run -- spec
```

### コマンド一覧

- `nike spec` — 言語仕様と命令対応表を表示します。
- `nike run <input.nike>` — 組み込みインタプリタでソースを解釈実行します。
- `nike compile <input.nike> -o <output> [--emit-c <output.c>] [--zig <path>]` — ソースを C 経由でネイティブ実行ファイルにコンパイルします。
  - `--emit-c <output.c>` — 生成した C ソースを書き出します（`-o` を付けなければ C 生成のみ）。
  - `-o <output>` — `zig cc` でネイティブ実行ファイルを生成します。
  - `--zig <path>` — 使用する Zig 実行ファイルのパスを指定します（既定は `zig`）。
- 引数なし / `help` / `--help` / `-h` — 使い方を表示します。

## 開発コマンド

```sh
zig build          # nike CLI をビルドして zig-out/bin にインストール
zig build test     # 言語・ランナー・C バックエンドのテストを実行
zig build run -- <args>  # ビルドして nike を実行
```

## 構成

```
.
├── build.zig            # Zig ビルド定義（exe / run / test ステップ）
├── src/
│   ├── main.zig         # CLI エントリポイントと引数解析
│   ├── lang.zig         # 字句解析・構文解析・診断・spec 出力（compileSource）
│   ├── ir.zig           # 命令(Instruction) と Program 定義
│   ├── runner.zig       # インタプリタと zig cc 呼び出し（ネイティブビルド）
│   ├── c_backend.zig    # IR から C ソースを生成するバックエンド
│   └── all_tests.zig    # zig build test のエントリ（各モジュールを取り込む）
└── examples/
    ├── hello.nike       # Hello World
    └── echo.nike        # echo（,[.,] 相当）
```

## サンプル

`examples/hello.nike` は標準的な Brainfuck の Hello World を NIKE語へ写したものです。

`examples/echo.nike` は `,[.,]` 相当の echo プログラムです。

## ライセンス

このリポジトリにはライセンスファイルが含まれていません。利用条件についてはリポジトリ所有者にご確認ください。
