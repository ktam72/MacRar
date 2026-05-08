# 变更日志

## [未发布]

### 追加
- MVVMアーキテクチャの採用（Model: UnrarArchive、ViewModel: ArchiveViewModel、View: MainView/LogTextView）
- unrarマルチスレッド解凍対応（`-mt2`パラメータ追加、DispatchQueue.concurrentでバックグラウンド実行）
- ログバッファリング機構（0.2秒間隔のTimerで一括フラッシュ、UI更新頻度を抑制）
- ログ表示をNSTextViewベースに変更（NSViewRepresentableでラップ、標準的なテキスト選択・コピーが可能）
- 解凍状態管理（idle/running/completed/failed）をUnrarArchiveモデルに追加

### 変更
- ログ出力の精简（デバッグログを削除、重要な処理ステップのみ出力）
- unrar標準出力の破棄（詳細ログ不要、エラー出力のみ記録）
- 展開先ディレクトリ命名規則の統一（`ファイル名_uncompressed`、スペースなし）
- unrarパス検索ロジックの最適化（バンドル内→バンドルリソース→開発ディレクトリの順）
- 解凍処理の非同期化（メインスレッドをブロックしない、100MB+ファイルでもUIフリーズ防止）
- プロジェクト名を `appMacRar` → `MacRar` に変更、ソースディレクトリもリネーム
- アプリケーション名を `MacRar.app` に統一（旧: `appMacRar.app`）

### 修复
- 100MB超のRARファイル解凍時のUIフリーズ問題
- ログ更新が追いつかない問題（バッファリング機構で解決）
- unrar実行ファイルのパス解決エラー（複数の検索パスを実装）
- ログの自動スクロールが正しく動作しない問題

### 文件关联
- 全対応フォーマット（14種）の Finder ファイル関連付けを実装
- `.lha` 拡張子のサポートを追加（LZH 形式として認識）
- ダブルクリックでアプリ起動 + 自動解凍を実装（NSApplicationDelegate + Apple Event）
- ViewModel を AppDelegate で直接保持するようアーキテクチャ変更
- 拡張子ベースの形式判定を全14形式に対応（辞書テーブルにリファクタリング）
- Apple Event からの file:// URL を正しく POSIX パスに変換するよう修正
- コールド起動時は `application(_:openFiles:)`、起動済み時は Apple Event ハンドラで処理

### 技术仕様
- 開発環境: macOS (Apple Silicon)、Xcode 17+、Swift 5.9+
- 依存ライブラリ: xcodegen（プロジェクト生成）、unrar 7.0（コマンドラインツール）
- ビルド手順: `xcodegen generate` → Xcodeでビルド・実行
