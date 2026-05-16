# NIKE language

Brainfuck 風のミニ言語です。ソースコードで使える単語は次の6語だけです。

- `AIニケ`
- `ニケ`
- `ブヒ夫`
- `ぷにけ`
- `ノルカス`
- `ミカゼ`

## v1 仕様

- ソースは UTF-8
- 空白は区切りとしてのみ使う
- 命令は **必ず2単語1組**
- v1 ではコメント非対応
- セルは 8-bit、加減算はラップアラウンド
- テープは右方向へ必要に応じて拡張
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

## 使い方

ローカルに Zig がある前提です。ネイティブ実行ファイルを作るときだけ `zig cc` を使います。

```powershell
zig build test
zig build
```

CLI:

```powershell
zig-out\bin\nike spec
zig-out\bin\nike run examples\hello.nike
zig-out\bin\nike run examples\echo.nike
zig-out\bin\nike compile examples\echo.nike --emit-c echo.c
zig-out\bin\nike compile examples\echo.nike -o echo.exe
zig-out\bin\nike compile examples\echo.nike -o echo.exe --zig C:\path\to\zig.exe
```

## サンプル

`examples\hello.nike` は標準的な Brainfuck の Hello World を NIKE語へ写したものです。

`examples\echo.nike` は `,[.,]` 相当の echo プログラムです。
