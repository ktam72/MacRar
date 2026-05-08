# MacRar プロジェクト設定

## ビルド前チェック

プロジェクトのビルド前に、以下のツールで問題がないことを確認すること。

| ツール | インストール状況 | 用途 |
|--------|----------------|------|
| cppcheck | ✅ インストール済み | C/C++ 静的解析（libarchive, unrar） |
| swiftlint | ✅ インストール済み | Swift 静的解析 |
| gitleaks | ✅ インストール済み | シークレット漏洩チェック |
| git-secrets | ✅ インストール済み | Git コミット内の機密情報チェック |
| semgrep | ✅ インストール済み | パターンベース静的解析 |
| trivy | ✅ インストール済み | 脆弱性スキャン |


### 実行手順

```bash
# Swift 静的解析
swiftlint --strict

# C/C++ 静的解析（libarchive）
cppcheck --enable=all Libs/libarchive/

# シークレットチェック
gitleaks detect --source . -v
git-secrets --scan

# 脆弱性スキャン
trivy fs .

# パターン解析
semgrep --config=auto .
```
