---
name: create-release
description: kotlin-slang の新しいバージョンをリリースする。GitHub Actions の workflow_dispatch をトリガーし、AAR を GitHub Release に公開する。
argument-hint: [version]
---

# kotlin-slang リリース作成

バージョン: $ARGUMENTS（省略時は手順 2 で提案する）

## 手順

1. **バージョン形式の確認**: X.Y.Z 形式で、`v` プレフィックスは付けない（`v0.5.0` ではなく `0.5.0`）。ワークフローの Validate version format が `v` 付きを拒否する

2. **最新リリースバージョンの確認**: リリースタグは GitHub Actions が作成し main には乗らない。README にもバージョンは書かれていない。必ずリモートを確認する:
   ```
   gh release list --limit 10
   ```
   - ローカルの `git describe` や README、特定のリリースだけを見て推測しないこと（既存のバージョンを指定すると、ワークフローの Ensure version is newer than every existing tag で失敗する）
   - `$ARGUMENTS` が省略されていたら、変更内容に応じて次のバージョンを提案する

3. **リリース内容の確認**: 前回リリースからの変更を確認する
   ```
   git fetch --tags
   git log <最新タグ>..origin/main --oneline
   ```
   - 変更内容とバージョンをユーザーに提示し、確認を取ってから次へ進む

4. **main の状態確認**:
   - `git status` で未コミットの変更がないか
   - `git log origin/main..HEAD --oneline` で push されていないコミットがないか
   - どちらかあればユーザーに警告する

5. **GitHub Actions トリガー**:
   ```
   gh workflow run release.yml --ref main -f version=<version>
   ```

6. **ワークフローの監視**: Slang をソースからビルドするため 20 分ほどかかる。バックグラウンドで待つ
   ```
   gh run list --workflow=release.yml --limit=1
   gh run watch <run-id> --exit-status
   ```

7. **結果の検証**:
   - `gh release view v<version> --json url,assets,body` で `kotlinslang-<version>.aar` が添付されていることを確認する
   - `git ls-remote --tags origin v<version>` でタグがトリガー時の main の HEAD を指していることを確認する
   - Slang を更新したリリースでは、AAR サイズが前回リリースから変わっていることも確認する（変わっていなければ古い Slang でビルドされた疑いがある）

8. **結果の報告**: リリース URL をユーザーに報告する

## 注意事項

- main ブランチから実行すること
- リリース後に README を更新する必要はない（バージョンは `<version>` プレースホルダー）
- コミットメッセージ・リリースノートにキャラ口調を使わないこと
