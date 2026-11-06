# 构建与 GitHub 发布

## 本地构建

需要 macOS 14+、Swift 6 和相互匹配的 Command Line Tools / Xcode 与 macOS SDK。检查：

```bash
swift --version
xcode-select -p
xcrun --sdk macosx --show-sdk-path
```

脚本使用当前 SDK，不依赖开发者机器上的固定 `MacOSX15.4.sdk` 路径。如需指定 SDK，设置 `SDKROOT`。

```bash
zsh scripts/build-app.sh arm64
zsh scripts/build-app.sh x86_64
zsh scripts/build-app.sh universal
```

通用版分别编译两个架构后用 `lipo` 合并，不依赖 SwiftPM 多架构模式所要求的完整 `xcbuild`。构建产物最低系统版本为 macOS 14。

输出：

```text
dist/LaunchpadOS.app
dist/LaunchpadOS_0.4.7_arm64.dmg
dist/LaunchpadOS_0.4.7_arm64.app.zip
dist/LaunchpadOS_0.4.7_arm64.sha256
```

其他架构文件名相应替换。构建会核对实际 Mach-O 架构，验证 `.app` 的 ad-hoc 签名、Info.plist 和 DMG 完整性。构建过程不启动应用，也不修改 `/Applications` 中已安装的版本及个人布局。`dist/LaunchpadOS.app` 会被当前构建更新；带架构名称的安装文件可共存。

## GitHub Actions

工作流：`.github/workflows/release.yml`，名称 **Build and release macOS**。

| 输出 | Runner | 内容 |
| --- | --- | --- |
| arm64 | macos-15 | Apple Silicon 原生 |
| x86_64 | macos-15-intel | Intel 原生 |
| universal | macos-15 | ARM64 + Intel 双架构 |

三个目标均输出 DMG 和 app ZIP。推送稳定版本标签后，全部构建、检查和发布校验通过，才创建并公开 Release。上传失败时最多留下草稿，可修复后重跑；已经公开的版本不覆盖，修复应递增版本后创建新标签。

Actions 页面手动运行分支，只生成 artifact，保留 14 天；选择已有版本标签手动运行则会尝试发布该标签。

## 发布版本

1. 在 `Resources/Info.plist` 更新 `CFBundleShortVersionString`（如 `0.4.8`）与递增的 `CFBundleVersion`。
2. 同步 README 版本说明与设置页“关于”中的版本文字。
3. 提交并推送源码和工作流。
4. 创建与 plist 一致的 `vX.Y.Z` 标签并推送：

```bash
python3 scripts/release.py version --tag v0.4.7
python3 -m unittest discover -s scripts -p test_release.py
git tag v0.4.7
git push origin v0.4.7
```

标签不一致会在构建前失败。当前只接受三段稳定版本号，不发布预发行标签。版本不一致不要移动已公开的标签。

依赖只使用系统框架和 Swift 标准库，无需上传 `.build`、`.cache`、`dist` 或个人 `layout.json` / `catalog.json`。`Package.swift`、Resources、Sources、scripts、docs、工作流和以后可能出现的 `Package.resolved` 应提交。

## 下载与校验

公开产物从 [Releases](https://github.com/JackerKun/LaunchpadOS/releases) 下载。`SHA256SUMS.txt` 包含六个安装文件的 SHA-256；`build-manifest.json` 记录版本、Build、架构、Git 提交和文件体积。发布前会检查三种架构齐全、版本 / 提交一致、文件非空、安装包哈希未改变。

```bash
# 在同一目录放置安装文件和校验清单
shasum -a 256 -c SHA256SUMS.txt
```

只下载部分文件时，其他未下载条目会报告不存在，可直接计算所下载文件的哈希并与清单中的对应行比较。

## 签名与验收边界

当前构建使用 ad-hoc 签名，没有 Apple Developer ID 与公证。完整性校验不等于 Apple 信任；不同 Mac 上首次启动可能触发系统开发者验证提示。工作流不绕过 Gatekeeper。后续如需正式签名和公证，可另行接入证书和 App Store Connect 凭据。

构建与签名检查不等于安装后 UI / 多屏 / 登录启动全套验收。实际截图来自现有安装版；新构建未自动启动，以免影响个人设置。仓库的 Python 测试覆盖发布标签、完整矩阵和损坏产物拦截；当前 Swift 包未声明单元测试 target。
