# ビルドエラー対策メモ

## リリースビルド（Archive）時のリンカエラー

### 症状

- デバッグビルド（Xcode の Run）は正常
- リリースビルド（Product > Archive）で以下のリンカエラーが発生

```
Undefined symbol: _archive_version_string
Undefined symbol: _archive_read_support_format_all
...
ld: symbol(s) not found for architecture x86_64
Linker command failed with exit code 1
```

### 原因

- `Libs/libarchive/libarchive.a` は **arm64 専用**（Universal バイナリではない）
- Archive 時、Xcode は `$(ARCHS_STANDARD)` に従い **arm64 + x86_64** の両方をビルドしようとする
- x86_64 向けにリンクする際、arm64 専用の `libarchive.a` からシンボルを解決できずエラーになる
- デバッグビルドは `ONLY_ACTIVE_ARCH` がデフォルトで YES のため、arm64 のみビルドされて問題が顕在化しない

### 対策

`project.yml` に `EXCLUDED_ARCHS` を追加し、x86_64 をビルド対象から除外する。

```yaml
settings:
  ARCHS: "$(ARCHS_STANDARD)"
  EXCLUDED_ARCHS: x86_64
```

#### 備考

- `EXCLUDED_ARCHS` は XcodeGen で正しく解釈され、`.xcodeproj` に反映される
- `ARCHS: arm64` のように単一アーキテクチャを指定する方法も試したが、XcodeGen が `$(ARCHS_STANDARD)` に変換するため期待通りにならなかった
- `ONLY_ACTIVE_ARCH: YES` を指定しても、Archive 時には無視されるため効果がない

### その他、実施した堅牢性強化

| 項目 | ファイル | 内容 |
| :--- | :--- | :--- |
| Zip Bomb 対策 | `ArchiveExtractor.swift` | 展開後合計サイズが 10GB を超えた場合に処理を中断する `maxTotalSize` を追加 |
| エントリ数制限 | `ArchiveExtractor.swift` | `maxEntryCount = 500_000`（元から存在） |
| Path Traversal 対策 | `ArchiveExtractor.swift` | `ARCHIVE_EXTRACT_SECURE_NODOTDOT` 等のセキュリティフラグ（元から存在） |
| Hardened Runtime | `project.yml` | `ENABLE_HARDENED_RUNTIME` は署名要件が厳格化されるため除外 |
| App Sandbox | `appMacRar.entitlements` | Sandbox 導入には保存先選択ダイアログ等の設計変更が必要なため、現状は無効 |

## SwiftLint コード品質修正

### 対応内容

SwiftLint（`swiftlint --strict`）を導入し、全37件の違反を修正。

| カテゴリ | 件数 | 対応内容 |
| :--- | :--- | :--- |
| 末尾ホワイトスペース | 10 | 自動修正（`swiftlint --fix`） |
| カンマ前後のスペース | 12 | 自動修正 |
| 末尾カンマ | 3 | 自動修正 |
| クロージャ未使用引数 | 1 | 自動修正 |
| Force Cast | 2 | `as!` → `guard let ... as?` で安全なアンラップに修正 |
| 識別子名が短すぎる | 4 | `a`→`archive`、`r`→`resultCode`、`p`→`value` にリネーム、`xz` は lint 抑制コメント |
| 循環的複雑度・関数長 | 2 | `extract()` を6つの private メソッドに分割（複雑度13→4、関数長77→23行） |
| 行長超過（120文字超） | 2 | メソッドシグネチャとエラーメッセージを改行分割 |
| 3要素タプル | 1 | `FormatSignature` 構造体に置き換え |

### 備考

- `ArchiveExtractor.swift` の `archive_read_new()` は `OpaquePointer?` を返すため `guard let` でアンラップが必要
- `archive_entry_pathname(entry)` 等の C API は非 optional の `OpaquePointer` を要求するため、呼び出し側で `entry!` の force unwrap を行う
