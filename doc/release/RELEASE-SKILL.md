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
| 安装包镜像 | R2 存储桶 `bujic-echo` 的 `calmbar/` 目录 | 国内直链 `https://downloads.bujic.cc/calmbar/CalmBar-X.Y.Z.dmg`，与 Release 是同一份 DMG |
| 镜像凭证 | `~/.config/cloudflare/config.env` | 权限 `600`，`CLOUDFLARE_R2_*`；仓库内不得出现任何 R2 凭证 |

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

### 2.2 同步 `doc/release/RELEASE.md`

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

`release.sh` 在正式执行前会校验 `doc/release/RELEASE.md` 是否已有对应版本章节，缺失会直接中止。先跑 dry-run 确认：

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
4. 用 `cloudflare-r2-s3` skill 把**同一份 DMG** 上传到 R2 的 `bujic-echo/calmbar/`（见第 5 节）。
5. 提交 `appcast.xml` 并推送 `main`。

```bash
# 2. 提交除 appcast 外的发版改动
git add app/Resources/Info.plist doc/release/RELEASE.md app/scripts/release.sh
git commit -m "release: vX.Y.Z"
git push origin main

# 3. tag + release
git tag -a vX.Y.Z -m "CalmBar X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z app/build/CalmBar-X.Y.Z.dmg \
  --verify-tag --title "CalmBar X.Y.Z" --notes "发版说明"

# 4. R2 镜像（详见第 5 节）
R2_UPLOAD="$HOME/.agents/skills/cloudflare-r2-s3-1.0.0/scripts/r2_uploader.py"
uv run --no-project --with boto3 --with python-dotenv python "$R2_UPLOAD" \
  upload app/build/CalmBar-X.Y.Z.dmg calmbar/CalmBar-X.Y.Z.dmg

# 5. appcast 最后上线
git add appcast.xml
git commit -m "release: vX.Y.Z appcast"
git push origin main
```

> 若先推送 appcast、后创建 Release，会出现短暂的安装包 404 窗口。

### 4.2 GitHub Release 说明

GitHub Release 说明应与 `doc/release/RELEASE.md` 保持一致，只保留用户关心的内容，并附安装说明。

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
2. 双击前在终端执行（只需这一步）：
   xattr -dr com.apple.quarantine ~/Downloads/CalmBar-X.Y.Z.dmg
3. 双击 DMG，把 CalmBar 拖入 Applications，从 Spotlight / 程序坞启动。
EOF
)"
```

`xattr -dr com.apple.quarantine` 会移除浏览器下载附加的隔离属性，Gatekeeper 不再拦截。DMG 去隔离后，拖出来的 App 不再带隔离属性，安装后不需要再对 `/Applications/CalmBar.app` 执行一次 `xattr`。

---

## 5. R2 镜像分发（国内直链）

GitHub Release 仍是 Sparkle 的更新源，**保持不变**；R2 只存放**同一份 DMG** 作为国内直链镜像，供官网与 README 的下载按钮使用。

| 项目 | 值 |
| :--- | :--- |
| 存储桶 | `bujic-echo` |
| 目录前缀 | `calmbar/` |
| 公网直链 | `https://downloads.bujic.cc/calmbar/CalmBar-X.Y.Z.dmg` |
| 凭证文件 | `~/.config/cloudflare/config.env`（`CLOUDFLARE_R2_*`，权限 `600`） |
| 上传方式 | `cloudflare-r2-s3` skill（`scripts/r2_uploader.py`） |

### 5.1 时机

**Git 提交、tag 与 GitHub Release 完成之后**执行，并且要在推送 `appcast.xml` 之前完成——这样官网/README 引用的直链不会出现 404 窗口。

```bash
# 1) 确认 GitHub Release 资产已就位
gh release view vX.Y.Z --json assets --jq '.assets[].name'

# 2) 上传同一份 DMG（签名只对这份字节有效，禁止重新打包）
R2_UPLOAD="$HOME/.agents/skills/cloudflare-r2-s3-1.0.0/scripts/r2_uploader.py"
uv run --no-project --with boto3 --with python-dotenv python "$R2_UPLOAD" \
    upload app/build/CalmBar-X.Y.Z.dmg calmbar/CalmBar-X.Y.Z.dmg

# 3) 校验直链与字节数
curl -sIL https://downloads.bujic.cc/calmbar/CalmBar-X.Y.Z.dmg | grep -iE "HTTP/|content-length"
stat -f%z app/build/CalmBar-X.Y.Z.dmg
```

`R2_UPLOAD` 指向本机 skill 目录，路径不同时改成 `cloudflare-r2-s3` skill 里 `scripts/r2_uploader.py` 的实际位置。依赖不装进系统 Python，统一用 `uv run --with` 临时拉起。

### 5.2 约定

- 对象名统一写 `calmbar/CalmBar-X.Y.Z.dmg`；桶根目录不放安装包。
- 上传的必须是**已签名、且已传给 `gh release create` 的那一份** DMG。重新构建或重新打包会改变字节，`edSignature` 与 `length` 立刻失效。
- 只新增本次文件，不删历史版本：旧直链会被用户收藏、被论坛与官网缓存引用。
- `appcast.xml` 的 `enclosure url` 继续指向 GitHub Releases，**不要**改成 R2 直链；R2 不参与自动更新，只做下载镜像。
- `bujic-echo` 是共享桶（其他项目如 `apk/` 也在里面），只操作 `calmbar/` 前缀，不要 `list` 后整桶清理。
- 仓库与提交记录里不得出现 Access Key、Secret Key 或 `config.env` 内容。

---

## 6. 验证清单

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
| R2 镜像直链 | `curl -sIL https://downloads.bujic.cc/calmbar/CalmBar-X.Y.Z.dmg` | HTTP 200，`content-length` 与本地 DMG 一致 |
| R2 对象路径 | `r2_uploader.py list` | 输出含 `calmbar/CalmBar-X.Y.Z.dmg`，其他前缀未被改动 |
| 远端 appcast | `gh api repos/chao-eng/CalmBar/contents/appcast.xml --jq .content \| base64 -d` | 含新版本 `<item>` |

> `raw.githubusercontent.com` 有 CDN 缓存，刚推送后直接 `curl` 可能仍返回旧内容；以 GitHub API 读取结果为准，Sparkle 稍后会自动拿到新版本。

---

## 7. 常见坑

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
11. **R2 镜像传了重新打包的 DMG**：镜像必须与 GitHub Release 资产字节完全一致（可用 `shasum -a 256` 比对），否则下载到的包与 `edSignature` 不匹配，签名校验失败。
12. **把 appcast 的 `enclosure url` 改成 R2 直链**：自动更新会跟着镜像域名走，代理、缓存与配额都受影响；R2 只承担手动下载，更新源固定 GitHub。

---

## 8. 发版最短路径

```bash
# 1. 更新 doc/release/RELEASE.md 的概览表与版本章节
# 2. 发版
cd app
./scripts/release.sh --dry-run
./scripts/release.sh minor

# 3. 验证
plutil -lint Resources/Info.plist
xmllint --noout ../appcast.xml
codesign --verify --deep --strict build/CalmBar.app

# 4. 推送代码（暂不含 appcast）
git add app/Resources/Info.plist doc/release/RELEASE.md app/scripts/release.sh
git commit -m "release: vX.Y.Z"
git push origin main

# 5. tag 与 Release
git tag -a vX.Y.Z -m "CalmBar X.Y.Z"
git push origin vX.Y.Z
gh release create vX.Y.Z app/build/CalmBar-X.Y.Z.dmg --verify-tag \
  --title "CalmBar X.Y.Z" --notes "发版说明"

# 6. R2 镜像：同一份 DMG → bujic-echo/calmbar/
R2_UPLOAD="$HOME/.agents/skills/cloudflare-r2-s3-1.0.0/scripts/r2_uploader.py"
uv run --no-project --with boto3 --with python-dotenv python "$R2_UPLOAD" \
  upload app/build/CalmBar-X.Y.Z.dmg calmbar/CalmBar-X.Y.Z.dmg
curl -sIL https://downloads.bujic.cc/calmbar/CalmBar-X.Y.Z.dmg | grep -iE "HTTP/|content-length"

# 7. appcast 最后上线
git add appcast.xml
git commit -m "release: vX.Y.Z appcast"
git push origin main
```
