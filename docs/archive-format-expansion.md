# アーカイブ形式拡張 設計書

## 背景

現在 MacRar は unrar CLI をバンドルし、RAR 形式の解凍のみに対応している。汎用アーカイバとするため、他形式の対応を計画する。

## 要件

- unrar は維持し、RAR/RAR5 の解凍に引き続き使用する
- X68000 で流通した LHA (LZH) 形式に対応する
- 対応形式はマジックバイトで自動判別し、ユーザーは拡張子を意識せず使える
- アプリ単体で完結し、Homebrew 等の外部パッケージマネージャに依存しない
- 配布可能なライセンスであること
- 絶対パス（/Users/ktam 等）をソースコードやドキュメントに含めず、どの環境でも clone してビルド可能にする

## 採用方式: libarchive（ソースビルド・静的リンク）+ unrar CLI 同梱

macOS 標準の `/usr/lib/libarchive.dylib` は使わず、libarchive のソースコードをプロジェクト外部の共有パスでビルドする。生成した `libarchive.a` と公開ヘッダ（`archive.h`, `archive_entry.h`）を `Libs/libarchive/` にコピーし、MacRar 実行ファイルに静的リンクする。Swift からは C API を直接呼び出す。

**libarchive ソース（外部）**: `<libarchive-source-dir>`
**プロジェクト内コピー先**: `Libs/libarchive/`（.a + 公開ヘッダのみ + COPYING）
**project.yml からの相対パス**: `Libs/libarchive/`（`SRCROOT` 基準）

### 選択理由

- **統一されたバージョン**: OSバージョンによる挙動差がなくなる
- **BSDライセンス**: コピーレフトなし、商用配布に制限なし
- **ビルド制御**: 必要なフォーマットだけ有効化でき、不要な依存を排除できる
- **外部プロセス不要**: ライブラリとして直接リンクするため Process() のオーバーヘッドがない
- **LHA対応**: libarchive は LZH 読み取りに対応しており X68000 要件を満たす

### トレードオフ

- ビルド手順が増える（CMake で libarchive をビルド）
- アプリサイズが libarchive.a の分だけ増加（約1.2MB）
- Swift から C API を呼ぶためのブリッジ層が必要

## アーキテクチャ

```
MacRar.app/
│
├── Contents/MacOS/
│   ├── MacRar (実行ファイル)
│   │   ├── Swift アプリコード
│   │   │   ├── ArchiveViewModel      形式判定 + ディスパッチ
│   │   │   ├── ArchiveFormat         マジックバイト判定
│   │   │   └── ArchiveExtractor      libarchive C API ラッパー
│   │   └── libarchive.a (静的リンク)
│   │       7z / ZIP / tar / gz / bz2 / xz
│   │       LZH / ISO / CAB / ARJ / CPIO
│   │
│   └── unrar  (RAR解凍用CLI, postCompileScript でコピー)
│
└── Contents/Resources/
    └── MacRar-icon.png  アプリアイコン
```

### 外部依存（プロジェクトルート Libs/）

```
プロジェクトルート/
├── Libs/
│   ├── libarchive/
│   │   ├── libarchive.a      静的ライブラリ（1.2MB, arm64）
│   │   ├── archive.h          公開ヘッダ
│   │   ├── archive_entry.h    公開ヘッダ
│   │   └── COPYING            BSD 2-Clause ライセンス条文
│   └── unrar/
│       ├── unrar              プリコンパイル済みバイナリ（arm64）
│       └── license.txt        unrar freeware ライセンス条文
├── LICENSE                    Apache 2.0（MacRar アプリケーション本体）
└── project.yml                XcodeGen 定義（リンク設定・ARCHS・postCompileScript）
```

### ディスパッチフロー

```
ユーザーがファイルをドロップ
        │
        ▼
  マジックバイト判定（先頭〜260バイト読み取り）
        │
        ├── RAR (52 61 72 21 ...)  ──→ unrar x（Process呼び出し）
        │
        ├── それ以外の対応形式      ──→ ArchiveExtractor（libarchive C API）
        │     7z/ ZIP/ gz/ bz2/ xz/
        │     tar/ LZH/ ISO/ CAB/ ARJ/ CPIO/ Z
        │
        └── 非対応                  ──→ エラー表示
```

### マジックバイト一覧

| 形式 | マジックバイト（16進） | オフセット |
|------|----------------------|-----------|
| RAR | `52 61 72 21 1A 07` | 0 |
| 7z | `37 7A BC AF 27 1C` | 0 |
| ZIP | `50 4B 03 04` | 0 |
| GZIP | `1F 8B 08` | 0 |
| BZIP2 | `42 5A 68` | 0 |
| LZH | `2D 6C 68` (`-lh`) | 2 |
| XZ | `FD 37 7A 58 5A 00` | 0 |
| LZIP | `4C 5A 49 50` | 0 |
| Z (compress) | `1F 9D` または `1F A0` | 0 |
| CAB | `4D 53 43 46` または `49 53 63 28` | 0 |
| ARJ | `60 EA` | 0 |
| TAR | `75 73 74 61 72` (`ustar`) | 257 |

### 対応形式一覧

| 形式 | 解凍エンジン | 備考 |
|------|------------|------|
| RAR / RAR5 | unrar CLI | `unrar x` を Process() 呼び出し、`-ep` なしでディレクトリ構造保持 |
| 7z | libarchive | `setlocale` で日本語ファイル名対応済み |
| ZIP | libarchive | jar, war, ear, xpi 含む |
| tar / tgz / tbz / txz | libarchive | フィルタ透過処理 |
| gz | libarchive | |
| bz2 | libarchive | |
| xz | libarchive | |
| lzip | libarchive | |
| LZH (LHA) | libarchive | `-lh5-`〜`-lh7-` 対応 |
| ISO | libarchive | |
| CAB | libarchive | |
| ARJ | libarchive | |
| CPIO | libarchive | |
| Z (compress) | libarchive | |

## ファイル構成

```
プロジェクトルート/
├── project.yml                  XcodeGen 定義（ARCHS / リンク設定 / スクリプト）
├── Package.swift                SwiftPM（現状 unused）
├── LICENSE                      Apache 2.0
├── .gitignore
├── README.md
├── Libs/
│   ├── libarchive/
│   │   ├── libarchive.a         静的ライブラリ（1.2MB, arm64）
│   │   ├── archive.h            公開ヘッダ（55KB）
│   │   ├── archive_entry.h      公開ヘッダ（35KB）
│   │   └── COPYING              BSD 2-Clause
│   └── unrar/
│       ├── unrar                プリコンパイル済みバイナリ（arm64）
│       └── license.txt          unrar freeware
├── appMacRar/
│   ├── AppEntry.swift           @main（windowResizability .contentSize 固定）
│   ├── ArchiveFormat.swift      マジックバイト判定（13形式）
│   ├── ArchiveExtractor.swift   libarchive C API ラッパー
│   ├── BridgingHeader.h         archive.h / archive_entry.h
│   ├── Info.plist               CFBundleIconFile = MacRar-icon
│   ├── MacRar-icon.png          アプリアイコン（1636x1658, Display P3）
│   ├── appMacRar.entitlements
│   ├── Models/
│   │   └── UnrarArchive.swift
│   ├── ViewModels/
│   │   └── ArchiveViewModel.swift  解凍ロジック + 状態管理
│   └── Views/
│       ├── MainView.swift          ドロップゾーン / バージョン表示 / ログ / 進捗
│       └── LogTextView.swift       NSTextView ラッパー
└── docs/
    └── archive-format-expansion.md  本設計書
```

## project.yml 設定

```yaml
targets:
  appMacRar:
    settings:
      ARCHS: arm64
      SWIFT_OBJC_BRIDGING_HEADER: appMacRar/BridgingHeader.h
      OTHER_LDFLAGS: "$(inherited) -L$(SRCROOT)/Libs/libarchive -larchive -lz -lbz2 -llzma -liconv"
      HEADER_SEARCH_PATHS: "$(inherited) $(SRCROOT)/Libs/libarchive"
    sources:
      excludes:
        - BridgingHeader.h
        - Libs
    postCompileScripts:
      - name: Copy unrar to MacOS
        script: cp "${PROJECT_DIR}/Libs/unrar/unrar" "${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/unrar"
```

### リンク設定の説明

| フラグ | 対象 | 理由 |
|-------|------|------|
| `-larchive` | libarchive.a | 静的ライブラリ本体 |
| `-lz` | zlib | libarchive の圧縮フィルタ依存 |
| `-lbz2` | bzip2 | libarchive の bzip2 フィルタ依存 |
| `-llzma` | lzma | libarchive の xz/lzma フィルタ依存 |
| `-liconv` | iconv | libarchive の文字コード変換依存 |

### ARCHS 制限

`ARCHS: arm64` に固定。libarchive.a が arm64 専用のため、Archive ビルドで x86_64 のリンクが失敗するのを防ぐ。将来ユニバーサルバイナリ対応時は libarchive を `CMAKE_OSX_ARCHITECTURES="arm64;x86_64"` で再ビルドし ARCHS 制限を解除する。

## 実装ファイル詳細

### BridgingHeader.h

```objc
#include <archive.h>
#include <archive_entry.h>
```

unrar は Process() 経由の CLI 呼び出しのみで、C++ ライブラリとの直接リンクは不要。

### ArchiveFormat.swift

- `ArchiveFormat` enum: 全13形式（rar + 12 libarchive形式）を定義
- `detect(from:)`: 先頭260バイトのマジックバイトを読み取り形式を判定
- `usesUnrar`: RAR形式のみ `true` を返し、ViewModel がディスパッチ先を判断
- `supportedFormatsText`: UI表示用の形式一覧文字列

### ArchiveExtractor.swift

libarchive の C API をラップする Swift クラス。

```
extract(archive:to:progress:log:) → 展開処理
```

重要な実装上の注意点:

**1. ロケール設定（7z 日本語ファイル名対応）**

macOS GUI アプリのデフォルトロケールは "C" (ASCII) であるため、7z アーカイブ内の UTF-16LE のパス名を変換する際、日本語等の非ASCII文字を含むエントリで `Pathname cannot be converted from UTF-16LE to current locale` エラーが発生する。これを回避するため、extract 先頭で `setlocale(LC_ALL, "en_US.UTF-8")` を呼び出し、libarchive の文字コード変換を UTF-8 で動作させる。

**2. chdir 方式の抽出**

絶対パス結合 + `archive_entry_set_pathname` では solid 7z アーカイブで抽出が失敗するケースがあった。現在は `FileManager.changeCurrentDirectoryPath` で展開先に chdir し、エントリのパス名は libarchive の生の値のまま `archive_read_extract` に渡す。これにより libarchive がパス解決を適切に処理する。

**3. 進捗計算**

事前カウントパスは行わない（solid 7z で2重読み取りが問題になるため）。代わりに `archive_filter_bytes(a, -1)` で読み取った圧縮済みバイト数を取得し、ファイルサイズとの比率で進捗を算出する。

**4. nil 安全な String 変換**

libarchive の C API が返す `const char *` は Swift で IUO（Implicitly Unwrapped Optional）として import される。NULL を返す可能性があるため、すべて `archive_error_string(a).map { String(cString: $0) } ?? "不明"` のように安全に変換する。

**5. ログ出力の抑制**

万単位のエントリを含むアーカイブではエントリごとのログ出力が CPU 負荷を招き、プログレスバーの更新が阻害される。そのため実行時のログ出力は最小限に抑えている：
- アーカイブオープン/クローズ、総エントリ数のみ出力
- 各エントリのファイル名や抽出結果（正常系）は出力しない
- WARN/RETRY/FATAL のみ出力（正常系は暗黙的に成功として扱う）

**6. セキュリティ対策**

悪意あるアーカイブに対する防御策として以下を実装している：

- **パストラバーサル対策**: `ARCHIVE_EXTRACT_SECURE_NODOTDOT`（`../` 対策）と `ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS`（絶対パス対策）を展開フラグに追加
- **シンボリックリンク攻撃対策**: `ARCHIVE_EXTRACT_SECURE_SYMLINKS` フラグにより、アーカイブ内の symlink が展開先ディレクトリ外を指す場合に拒否
- **DoS対策**: エントリ数上限 `500,000` を設定。超過時は展開を中断してエラーとする
- **CVE対策**: 静的リンクする libarchive はソースからビルドしており、最新バージョンに追従。既知の Critical/High な CVE（CVE-2024-37407, CVE-2025-5914, CVE-2026-5121 等）は解消済み

API 利用パターン:

```swift
setlocale(LC_ALL, "en_US.UTF-8")

let a = archive_read_new()
archive_read_support_filter_all(a)    // gz/bz2/xz 透過
archive_read_support_format_all(a)    // 全フォーマット
archive_read_open_filename(a, path, 10240)

// chdir で展開先に移動
let fm = FileManager.default
let originalCWD = fm.currentDirectoryPath
fm.changeCurrentDirectoryPath(destination)
defer { fm.changeCurrentDirectoryPath(originalCWD) }

var entryCount = 0
var entry: OpaquePointer?
while archive_read_next_header(a, &entry) == ARCHIVE_OK {
    entryCount += 1
    guard entryCount <= 500_000 else {
        throw ArchiveExtractionError.extractFailed("エントリ数制限超過")
    }

    let flags = ARCHIVE_EXTRACT_TIME
              | ARCHIVE_EXTRACT_SECURE_NODOTDOT
              | ARCHIVE_EXTRACT_SECURE_SYMLINKS
              | ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS
              | ARCHIVE_EXTRACT_UNLINK
    let result = archive_read_extract(a, entry, flags)
    // result: ARCHIVE_OK / ARCHIVE_WARN / ARCHIVE_RETRY / ARCHIVE_FATAL

    let bytesConsumed = archive_filter_bytes(a, -1)
    if fileSize > 0 {
        progress(min(Double(bytesConsumed) / Double(fileSize), 1.0))
    }
}
```

### ArchiveViewModel.swift

`processFile(at:)` の処理フロー:

1. `ArchiveFormat.detect(from:)` でマジックバイト判定
2. `createExtractionDirectory(for:)` で `ファイル名_uncompressed/` を作成
3. RAR → `extractWithUnrar(at:to:)`（Process() 呼び出し、`-ep` なしで構造保持）
4. 他形式 → `extractWithLibArchive(at:to:)`（ArchiveExtractor + chdir + 進捗）

unrar の引数: `["x", "-y", "-mt2", path, destination]`（マルチスレッド、`-ep` なし）

`findUnrarPath()` の検索順:
1. `Bundle.main.executableURL` の同階層（バンドル内コピー）
2. `#filePath` からプロジェクトルートを割り出し `Libs/unrar/unrar`（開発環境フォールバック）

unrar バージョン取得はバックグラウンドキューで非同期的に行い、init 完了後に `@Published var unrarVersionText` を更新する（同期待ちによる SIGABRT 防止）。

### AppEntry.swift

```swift
@main
struct AppMacRar: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentSize)  // 固定サイズ
    }
}
```

ウィンドウサイズは 600×800 固定、リサイズ不可。

### MainView.swift

- 上部: libarchive / unrar バージョンラベル（`.font(.system(size: 22))`）
- 中央: ドロップゾーン（破線枠、対応形式一覧表示）
- 下部: ログエリア（NSTextView, 等幅フォント, 自動スクロール, 選択/コピー可能）
- クリアボタン、行数表示
- 処理中はプログレスバー（0-100%）とパーセント数値を表示

### Info.plist

```xml
<key>CFBundleIconFile</key>
<string>MacRar-icon</string>
```

形式の関連付け（CFBundleDocumentTypes）は未設定。ユーザーが Finder で手動設定する運用。

## libarchive ビルド手順

### 前提

- Xcode Command Line Tools インストール済み
- CMake インストール済み

### ビルドコマンド

```bash
cd <libarchive-source-dir>

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="arm64" \
  -DENABLE_TAR=OFF \
  -DENABLE_CPIO=OFF \
  -DENABLE_CAT=OFF \
  -DENABLE_UNSHAR=OFF \
  -DENABLE_NETTLE=OFF \
  -DENABLE_OPENSSL=OFF \
  -DENABLE_LZ4=OFF \
  -DENABLE_ZSTD=OFF \
  -DENABLE_EXPAT=OFF \
  -DENABLE_PCREPOSIX=OFF \
  -DENABLE_LIBXML2=OFF \
  -DENABLE_TEST=OFF \
  -DENABLE_LZO=OFF \
  -DENABLE_CNG=OFF \
  -DENABLE_LIBB2=OFF

cmake --build build
```

### プロジェクトへの取り込み

```bash
cp build/libarchive/libarchive.a <project_dir>/Libs/libarchive/
cp libarchive/archive.h          <project_dir>/Libs/libarchive/
cp libarchive/archive_entry.h    <project_dir>/Libs/libarchive/
```

ビルドに成功したら COPYING（ライセンス条文）も一緒にコピーしてコミットする。

### libarchive.a の構成

| ファイル | サイズ | 説明 |
|---------|--------|------|
| `libarchive.a` | 1.2MB | 静的ライブラリ |
| `archive.h` | 55KB | 公開ヘッダ |
| `archive_entry.h` | 35KB | 公開ヘッダ |

## X68000 LHA の考慮点

### 文字コード（未実装）

X68000 上の LHA アーカイブはファイル名が Shift-JIS で格納されている。現時点では変換処理は実装していない。libarchive の `archive_entry_pathname()` が返す生バイト列が macOS 上で正しく表示されないケースが確認された場合に対応する。

実装方針:

```swift
let rawBytes = archive_entry_pathname(entry)
// Shift-JIS → UTF-8 変換
let sjisEncoding = CFStringConvertEncodingToNSStringEncoding(
    CFStringEncoding(CFStringEncodings.shiftJIS.rawValue))
let utf8Name = NSString(data: rawBytes, encoding: sjisEncoding)
```

### 自己解凍形式

X68000 では `.EXE` 形式の自己解凍 LHA も流通していたが、実行ファイルでありアーカイブとしての抽出は不可能。対応対象外とする。

## 既知の対応実績

- **7z 日本語ファイル名** — `setlocale(LC_ALL, "en_US.UTF-8")` で対応済み。macOS GUI アプリのデフォルトロケールが "C" (ASCII) であるため、UTF-16LE パス名の変換が失敗する問題を修正
- **大量エントリアーカイブのパフォーマンス** — エントリごとのログ出力を削除し、67944エントリの 7z (120MB) を約13秒で展開可能に
- **セキュリティフラグ追加** — `ARCHIVE_EXTRACT_SECURE_SYMLINKS` および `ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS` を展開フラグに追加、エントリ数上限を設定
- **libarchive 最新化** — ソースを最新 master に追従し、既知の CVE (Critical/High) を解消
- **ライセンス同梱** — Apache 2.0（MacRar本体）、BSD 2-Clause（libarchive）、unrar freeware（unrar）の各ライセンス条文を同梱
- **絶対パス排除** — `/Users/ktam` 等の絶対パスを削除し、`#filePath` 相対解決またはプレースホルダに置換。誰でも clone してビルド可能に

## 残課題

- libarchive の LHA/LZH 品質は p7zip ほど検証されていない。X68000 実機アーカイブでのテスト必須
- 一部の 7z ファイル（Zstandard 圧縮）は `ENABLE_ZSTD=ON` で libarchive をリビルドが必要
- LHA Shift-JIS ファイル名の文字コード変換は未実装
- Finder の「このアプリで開く」対応（CFBundleDocumentTypes）は未設定。ユーザーが手動で関連付け

## リスクと注意点

- libarchive CMake ビルド時は `build/version` ファイルが必要。git checkout 等で復元可能
- p7zip の LGPL 表記が不要になった（libarchive は BSD ライセンス）
- libarchive.a の静的リンクにより、アプリ実行ファイルに ~1.2MB のサイズ増加
- unrar は引き続き CLI バイナリとして同梱。RAR 品質は従来通り
- アーキテクチャは arm64 限定。ユニバーサルバイナリ対応時は libarchive の CMake 設定変更 + ARCHS 制限解除が必要
