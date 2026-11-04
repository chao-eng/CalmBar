# CalmBar 发版 Skill：版本管理 · 通用 DMG · Sparkle 自动更新

> 适用范围：CalmBar macOS 客户端的版本递增、DMG 打包、EdDSA 签名、appcast 发布、GitHub Release 与发版说明同步。
> 本流程已在 v2.5.0 完整跑通，可直接复用。

---

## 1. 唯一事实来源

| 项目 | 位置 | 说明 |
| :--- | :--- | :--- |
| 版本号 | `app/Resources/Info.plist` | `CFBundleShortVersionString`（展示版本）+ `CFBundleVersion`（Sparkle 比较用 build 号） |
| 更新源 | `appcast.xml`（仓库根目录） | Sparkle 从 `main` 分支的该文件读取更新 |
| 更新公钥 | `Info.plist` 的 `SUPublicEDKey` | 私钥在登录钥匙串，由 Sparkle 管理，不要提交 |
| 通用 App | `app/build_app.sh` | arm64 + x86_64 编译、`lipo` 合并、内嵌 Sparkle、ad-hoc 签名 |
| DMG | `app/scripts/make-dmg.sh` | 生成含 Applications 快捷方式的 UDZO DMG |
| 一键发版 | `app/scripts/release.sh` | 版本递增、构建、DMG、EdDSA 签名、写入 appcast |

**硬性规则**

- `CFBundleVersion` 必须单调递增，只改展示版本号会导致已安装用户收不到更新。
- 版本号只改 `Info.plist`，不要同时维护多份版本常量。
- sparkle 的 `edSignature` 与 `length` 绑定 DMG 字节，签名后**禁止重新打包**。

---

## 2. 发布前准备

### 2.1 找到真正的上一版基线

旧版本不一定有 tag。不要用 `HEAD~1` 猜测，先确认上一版发布提交：

```bash
git log --oneline --all --grep="release" -10
# 或查看历史提交中的版本常量
git show <commit>:app/build_app.sh | grep VERSION
```

然后对比基线到当前的全部改动：

```bash
git log --oneline <上一版提交>..HEAD
git diff --stat <上一版提交>..HEAD -- app/Sources
```

> 经验：v2.5.0 的上一版基线是 `566e5a2`，而不是 `HEAD~1`；只对比 `HEAD~1` 会漏掉菜单栏面板重构和系统监控等已合入功能。

### 2.2 同步 `doc/RELEASE.md`

必须同时更新两处：

1. 顶部「版本发布概览」表新增一行。
2. 正文新增 `## vX.Y.Z` 章节，按实际代码差异归纳，语言简短。

**只写已经上线的功能。** 例如 v2.5.0 中声音分区尚未上线，发版说明中不能写「五个分区 / 声音分区」，应写「温控 / 守护 / 工具 / 监控四个分区」。

建议按用户可感知维度分组：

- UI / 交互重构
- 新增功能模块
- 版本管理与分发链路
- 缺陷修复
- 安装注意事项（临时签名场景）

### 2.3 发版说明同步检查

`release.sh` 在正式执行前会校验 `doc/RELEASE.md` 是否已有对应版本章节，缺失会直接中止。先跑 dry-run 确认：

```bash
cd app
./scripts/release.sh --dry-run
```

输出会显示：

- 新版本号与 build 号
- `RELEASE.md` 检查状态（已包含 / 缺失）
- DMG 名称与下载地址

---

## 3. 构建与签名

```bash
cd app
./scripts/release.sh minor   # 2.5.0 → 2.6.0；patch / major 同理
```

脚本按顺序执行：

1. `Info.plist` 版本号 +1，build 号 +1。
2. `build_app.sh`：分别编译 arm64 与 x86_64，`lipo` 合并主程序与 Helper。
3. 内嵌 `Sparkle.framework`，补 `@executable_path/../Frameworks` rpath。
4. 组装资源与 `Info.plist`，ad-hoc 深签名。
5. `make-dmg.sh`：临时目录 + `/Applications` 快捷方式，生成 UDZO DMG。
6. `sign_update` 生成 EdDSA 签名，写入 appcast 新 `<item>`。
7. 任一步失败回滚 `Info.plist` 版本号。

**关键产物**

- App：`app/build/CalmBar.app`
- DMG：`app/build/CalmBar-X.Y.Z.dmg`
- appcast：仓库根 `appcast.xml`

**签名密钥**

- Sparkle 只要求一个 EdDSA 密钥，多项目可复用。
- 换机器时需要用 `generate_keys -x` 导出、`-f` 导入，否则无法再签发更新。
- `sign_update` 读取登录钥匙串，在受限沙箱内会失败，需在普通终端执行。

---

## 4. Git 与 GitHub Release

### 4.1 推荐的发布顺序

先上传安装包，再让 appcast 上线，避免用户拿到 404 的更新地址：

1. 执行 `release.sh`，本地生成 DMG 与 appcast。
2. 提交版本号、发版说明与脚本改动，**暂时不提交 appcast**，推送 `main`。
3. 创建 tag 与 GitHub Release，上传 DMG。
4. 提交 `appcast.xml` 并推送 `main`。

```bash
# 2. 提交除 appcast 外的发版改动
git add app/Resources/Info.plist doc/RELEASE.md app/scripts/release.sh
git commit -m "release: vX.Y.Z"
git push origin main

# 3. tag + release
git tag -a vX.Y.Z -m "CalmBar X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z app/build/CalmBar-X.Y.Z.dmg \
  --verify-tag --title "CalmBar X.Y.Z" --notes "发版说明"

# 4. appcast 最后上线
git add appcast.xml
git commit -m "release: vX.Y.Z appcast"
git push origin main
```

> 若先推送 appcast、后创建 Release，会出现短暂的安装包 404 窗口。

### 4.2 GitHub Release 说明

GitHub Release 说明应与 `doc/RELEASE.md` 保持一致，只保留用户关心的内容，并附安装说明。

更新已有 Release 说明：

```bash
gh release edit vX.Y.Z --notes "$(cat <<'EOF'
## CalmBar X.Y.Z

### 主要变更
- ...

### 安装说明：临时签名未经过 Apple 公证
DMG 采用 ad-hoc 签名，未经过 Apple 公证（公证需要付费的 Developer ID）。
macOS Sequoia 可能在挂载前拦截，且弹窗不再提供「仍要打开」按钮。

1. 下载 DMG。
2. 双击前在终端执行：
   xattr -dr com.apple.quarantine ~/Downloads/CalmBar-X.Y.Z.dmg
3. 双击 DMG，把 CalmBar 拖入 Applications。
4. 安装后再执行：
   xattr -dr com.apple.quarantine /Applications/CalmBar.app
5. 通过 Spotlight / 程序坞启动。
EOF
)"
```

`xattr -dr com.apple.quarantine` 会移除浏览器下载附加的隔离属性，Gatekeeper 不再拦截。`/Applications` 无写入权限时可在第二条命令前加 `sudo`。

---

## 5. 验证清单

| 检查项 | 命令 | 预期 |
| :--- | :--- | :--- |
| plist 格式 | `plutil -lint app/Resources/Info.plist` | OK |
| appcast 格式 | `xmllint --noout appcast.xml` | 无报错 |
| 通用二进制 | `lipo -info app/build/CalmBar.app/Contents/MacOS/CalmBar` | `x86_64 arm64` |
| App 签名 | `codesign --verify --deep --strict app/build/CalmBar.app` | 通过 |
| DMG 签名 | `codesign --verify --strict app/build/CalmBar-X.Y.Z.dmg` | 通过 |
| DMG 可挂载 | `hdiutil attach ...` | 挂载成功，内含 Applications 快捷方式 |
| 签名可用 | `sign_update app/build/CalmBar-X.Y.Z.dmg` | 输出 `edSignature` |
| App 可启动 | 启动构建产物观察日志 | 无 Sparkle / 崩溃报错 |
| Release 资产 | `gh release view vX.Y.Z --json assets` | 包含 DMG 且大小正确 |
| 资产可下载 | `curl -sIL <DMG URL>` | HTTP 200 |
| 远端 appcast | `gh api repos/chao-eng/CalmBar/contents/appcast.xml --jq .content \| base64 -d` | 含新版本 `<item>` |

> `raw.githubusercontent.com` 有 CDN 缓存，刚推送后直接 `curl` 可能仍返回旧内容；以 GitHub API 读取结果为准，Sparkle 稍后会自动拿到新版本。

---

## 6. 常见坑

1. **沙箱限制**：`hdiutil` 访问 `/dev/rdisk*`、`sign_update` 读钥匙串、`swift build --disable-sandbox` 需要在外层终端执行。
2. **Sparkle 下载进程读不到 App 配置**：代理必须通过 App 内的 `127.0.0.1` 回环转发服务生效，不能只设置 `URLSession` 代理。
3. **DMG 签名后不要重新打包**：重新打包后 `edSignature` 与 `length` 失效，必须重新签名并重传。
4. **build 号不递增等于没发版**：Sparkle 只比较 `CFBundleVersion`。
5. **PlistBuddy 会重排键顺序**：手动改版本号时直接编辑 `<string>`，避免产生巨大 diff；`release.sh` 自动改版会接受该重排。
6. **旧版本没有 tag**：对比基线要通过 release 提交与历史 `VERSION` 常量确认，不能默认 `HEAD~1`。
7. **不要把未上线功能写进发版说明**：以实际对外可见功能为准，例如声音分区未上线就不提。
8. **先 Release 后 appcast**：否则更新源指向不存在的安装包。
9. **ad-hoc 签名 = 首次安装需清隔离**：README 与 GitHub Release 都要写清 `xattr` 命令。
10. **App 未放入 `/Applications`**：自动更新仍可能工作，但建议统一安装到应用程序目录，减少权限与替换问题。

---

## 7. 发版最短路径

```bash
# 1. 更新 doc/RELEASE.md 的概览表与版本章节
# 2. 发版
cd app
./scripts/release.sh --dry-run
./scripts/release.sh minor

# 3. 验证
plutil -lint Resources/Info.plist
xmllint --noout ../appcast.xml
codesign --verify --deep --strict build/CalmBar.app

# 4. 推送代码（暂不含 appcast）
git add app/Resources/Info.plist doc/RELEASE.md app/scripts/release.sh
git commit -m "release: vX.Y.Z"
git push origin main

# 5. tag 与 Release
git tag -a vX.Y.Z -m "CalmBar X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z app/build/CalmBar-X.Y.Z.dmg --verify-tag \
  --title "CalmBar X.Y.Z" --notes "发版说明"

# 6. appcast 最后上线
git add appcast.xml
git commit -m "release: vX.Y.Z appcast"
git push origin main
```
