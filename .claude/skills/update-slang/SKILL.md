---
name: update-slang
description: Slang サブモジュールのバージョンを更新し、Android 向け静的ライブラリと AAR をビルドして検証する。ローカルでのビルドが必要。
argument-hint: [slang-version]
---

# Slang 更新

更新先バージョン: $ARGUMENTS（例: v2026.19。省略時は手順 1 で決める）

swift-slang と違い、ヘッダーのコピーとバイナリリリースは不要。JNI は `slang/include` を直接参照し、AAR はリリース時に CI が Slang をソースからビルドして作る。このスキルの成果物は「サブモジュールのピン + Makefile の追従 + README」のコミットだけ。

## 前提条件の確認

```bash
cmake --version && ninja --version && java -version
ls "$HOME/Library/Android/sdk/ndk/28.2.13676358"
```

NDK のバージョンは `Makefile` の `ANDROID_NDK` と `kotlinslang/build.gradle.kts` の `ndkVersion` に合わせる。

## 手順

### 1. 更新先バージョンの決定

基準は Slang 本家（shader-slang/slang）の最新リリース:

```bash
gh release list -R shader-slang/slang --limit 10
git -C slang describe --tags   # 現在のピン
```

- `$ARGUMENTS` が省略されていたら、`Latest` が付いたリリースを提案してユーザーに確認する
- 現在のピンが既に最新なら、更新不要であることを報告して終了する
- 途中のバージョンを飛ばす場合は、飛ばしたリリースのノートも確認する（`gh release view <tag> -R shader-slang/slang`）。破壊的変更があればユーザーに報告する。リリースノートが空のバージョンもあるので、その場合はそう伝える

swift-slang も同じ Slang をピンしている。向こうのピンは参考情報として確認し、ずれる場合はユーザーに一言伝える（止める理由にはしない）:

```bash
gh release list -R shivaduke28/swift-slang --limit 10   # slang-binary/<version> タグ
```

### 2. ブランチ作成

main に直接コミットしない。最新の main から切る:

```bash
git fetch origin
git switch -c update-slang-<version> origin/main
```

### 3. サブモジュール更新

```bash
git submodule update --init --recursive
OLD=$(git -C slang describe --tags)
git -C slang fetch --tags
git -C slang checkout <version>
git -C slang submodule update --init --recursive
```

最後の行を忘れないこと。Slang 自体が `external/` 以下に多数のサブモジュールを持ち、バージョン間で追加・更新される。チェックアウトしただけでは古いままになる。

### 4. ヘッダー差分の確認

```bash
git -C slang diff --stat "$OLD" <version> -- include/
git -C slang diff "$OLD" <version> -- include/slang.h
```

`kotlinslang/src/main/cpp/kotlinslang_jni.cpp` と `spike/smoke/*.cpp` が使っている API に削除・シグネチャ変更がないか確認し、結果をユーザーに報告する。

### 5. 静的ライブラリのビルド

```bash
make clean
make build
make verify
```

- **`make clean` は必須**。`generators` ターゲットは `slang/generators/` が存在するとスキップするため、clean しないと旧バージョンのジェネレータで新バージョンをビルドしてしまう
- ホストのジェネレータと arm64-v8a の両方をビルドするので 10〜30 分かかる。バックグラウンドで実行する

**新しい依存ライブラリの確認**: Slang は更新で外部依存を増やすことがある（v2026.13.1 で cmark-gfm が追加された）。

```bash
find slang/build-android-arm64 -name "*.a" -not -path "*/Release/lib/*"
```

以下は既知なので無視してよい:

- `external/miniz/libminiz.a`
- `external/lz4/build/cmake/liblz4.a`
- `external/cmark/src/libcmark-gfm.a`

それ以外の `.a` が出てきたら、`Makefile` の `android-arm64` ターゲットの strip・cp・`llvm-ar -M` スクリプト（`addlib`）の3か所に追加してビルドし直す。パスが変わって strip が失敗した場合も同じ3か所を直す。

**ビルドのトラブルシューティング**:

- ホストの generators configure が `building DXC from source` と出して DXC のクローンとビルドを始める場合: `SLANG_ENABLE_DXIL` が効いていない。`Makefile` の2つの cmake 呼び出しの両方に `-DSLANG_ENABLE_DXIL=OFF` を渡している（v2026.18 から macOS で必要）。途中で止めた場合は `slang/generators` を削除してからやり直す
- 新しい cmake オプションやターゲットが原因で失敗した場合、swift-slang の `Makefile` と `.claude/skills/update-slang/SKILL.md` に同じバージョンでの対処が書かれていることが多い。先にそちらを見る
- cmake 呼び出しは `generators` と `android-arm64` の2つ。フラグを足すときは両方に必要か確認する

### 6. AAR のビルド

```bash
ls -l kotlinslang/build/outputs/aar/kotlinslang-release.aar   # 更新前のサイズ（あれば）
./gradlew :kotlinslang:assembleRelease
ls -l kotlinslang/build/outputs/aar/kotlinslang-release.aar
```

- ここで `libkotlinslang.so` がリンクされる。マージ漏れの依存ライブラリがあると undefined symbols で失敗するので、実機がなくてもこのステップまでは必ず通す
- AAR サイズが更新前から変わっていることを確認する。変わっていなければ古い `libSlangCompiler.a` をリンクしている疑いがある

### 7. 実機テスト

instrumented test は実機（arm64-v8a）が必要。`adb` は PATH にないのでフルパスで確認する:

```bash
"$HOME/Library/Android/sdk/platform-tools/adb" devices
./gradlew :kotlinslang:connectedAndroidTest
./gradlew :sample:connectedAndroidTest
```

- 両方とも `BUILD SUCCESSFUL` とテスト件数まで確認する
- `:sample` は R8 有効のリリースビルドに対して走り、consumer ProGuard ルールを検証する
- `INSTALL_FAILED_USER_RESTRICTED` は端末側の USB インストール確認ダイアログが原因。ユーザーに端末を操作してもらって再実行する。`:kotlinslang` と `:sample` は別パッケージなので、それぞれで確認が出る。実行前に「端末でインストールを許可してほしい」と伝えておく
- 端末が接続されていない場合はユーザーに接続を頼む。テストなしで進める場合は、未実行であることを PR 本文に明記する

コンパイル時間の変化を見たい場合は `CompileBenchmarkTest` の結果を更新前後で比べる（任意）。

### 8. README.md 更新

`README.md` の Architecture 節にあるピンの表記を更新する:

```
- Slang is pinned to the same version as swift-slang (currently `<version>`)
```

### 9. コミット

```bash
git add slang Makefile README.md
git commit
```

コミットメッセージは `Update Slang to <version>`。Makefile を変更した場合は理由を本文に書く。キャラ口調は使わない。

### 10. PR 作成

ユーザーに確認してから push して PR を作る。本文には以下を書く:

- 旧バージョン → 新バージョン
- Makefile の変更とその理由（あれば）
- ヘッダー差分の確認結果
- AAR サイズの変化
- 実行した検証（`make clean && make build`、各 `connectedAndroidTest` の件数と端末名）。実行できなかったものはそう書く

## 注意事項

- ビルドは macOS で実行すること（CI のリリースビルドは ubuntu-latest。ホスト依存の対処を入れたら Linux でも通るか考える）
- ビルド成果物（`build/`、`slang/build-*/`、`slang/generators/`）は .gitignore されている
- サブモジュールのピンを変えただけではリリースされない。マージ後に `/create-release` で AAR を公開する
