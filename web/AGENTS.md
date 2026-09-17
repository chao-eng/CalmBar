# AGENTS.md —— CalmBar 官网前端工程约束规范

> 范围：本文件只约束 `web/` 目录（CalmBar 官方网站重构）。
> 技术栈：Astro + Vue Islands + Tailwind CSS v4 + MDX + shadcn-vue。
> 旧静态站 `site/` 为只读对照物；Swift 主工程 `app/` 不受本文件约束。
> 信息架构参考：`/Users/guojc/Downloads/参考/LightC — Windows C 盘智能清理工具 _ 官方网站.html`（干净的产品官网风、双渠道下载区、FAQ 手风琴、作者与鸣谢区）。

## 🚫 硬性红线（违反即错）

| 编号  | 规则                                                                                                                        |
|-------|-----------------------------------------------------------------------------------------------------------------------------|
| RL-01 | 输出语言：面向用户的文案与代码注释用简体中文，标识符与代码保持英文；提交信息沿用仓库既有的英文 Conventional Commits 风格（见 `git log`） |
| RL-02 | 工程边界：只允许新增/修改 `web/` 内文件；`site/`、`app/`、`doc/`、`README.md` 一律只读。唯一例外：仓库根 `LICENSE`（Apache License 2.0 全文），经作者确认后可维护 |
| RL-03 | 事实来源：版本号、功能描述、性能数据、授权信息只能取自 `README.md`、`doc/` 与旧站 `site/index.html`（只读）；禁止编造、禁止自行造数 |
| RL-04 | 类型安全：禁止 `any`、`@ts-ignore`、`@ts-nocheck`；禁止非必要的 `as` 断言与非空断言 `!`                                        |
| RL-05 | 组件检索：新增任何 UI 组件前，必须先用 shadcnVue MCP 检索并取回 add 命令；禁止凭记忆手写 shadcn-vue 组件名或 API               |
| RL-06 | 组件优先：轮播、手风琴、标签页、弹窗、导航菜单、滚动区等已有 shadcn-vue 组件的 UI，禁止手写等价实现                            |
| RL-07 | 单一 UI 体系：禁止引入 Element Plus、Naive UI、Vuetify、Ant Design Vue、UnoCSS、Bootstrap 或独立 `.scss` 体系                 |
| RL-08 | 禁状态库：禁止引入 Vue Router、Pinia、Vuex 或任何全局状态库；官网是静态单页 + 锚点导航                                        |
| RL-09 | 水合克制：交互 Vue 组件必须显式声明 `client:*`；默认 `client:visible`，仅首屏必需交互用 `client:load`，禁止无差别 `client:load` |
| RL-10 | 颜色：禁止裸色值（`#0071e3`、`rgb(...)`、`bg-[#fff]`），必须使用 Tailwind token 或 `src/styles/globals.css` 的 CSS 变量         |
| RL-11 | 图片：必须带 `width` + `height` 或 `aspect-ratio`；资源统一位于 `web/public/images/`；禁止跨目录引用 `../site/images/**`        |
| RL-12 | 文件长度：`.astro` / `.vue` ≤ 250 行，`.ts` ≤ 400 行，`.mdx` ≤ 400 行；超出必须拆分                                          |
| RL-13 | 逻辑外置：`.astro` 组件只做数据取值与渲染；条件分支、数据变换必须放 `src/lib/**` 或 `.vue` 组件                                |
| RL-14 | 交付验证：每次改动后必须执行 `npm run check` 与 `npm run build`，任一失败不得交付                                              |
| RL-15 | 禁止读取 `node_modules/`、`dist/`、`.astro/`；需要组件用法时走 shadcnVue MCP                                                   |

---

## ⚙️ 编码原则

1. **方案先行**

- 版块结构、交互方式存在多种理解时，先列出方案再确认，不做假设
- 涉及新增依赖、改动信息架构、引入 i18n 时必须先确认

2. **简洁至上**

- 用最少代码解决问题；Astro 组件默认零 JS，能用 HTML + Tailwind 表达的绝不写 Vue
- 自检：「这个交互真的需要岛屿水合吗？静态渲染能否满足？」

3. **精准修改**

- 只改必须改的部分，保持既有风格；只清理本次改动产生的孤儿代码
- `src/components/ui/` 是 CLI 生成物，需要定制时在外层包装组件里覆盖，不回改生成物

4. **内容与呈现分离**

- 文案、FAQ 条目、功能介绍长文放 MDX / `src/content/**`，组件只负责布局与样式
- 站点常量（版本号、下载地址、系统要求）收口到 `src/lib/site.ts`，禁止在组件里散落硬编码

5. **顺序交付**

- 按版块顺序推进并可独立验收：导航 → Hero → 产品截图 → 功能介绍 → 信任背书 → 下载 → FAQ → 作者介绍 → 页脚
- 每完成一个版块即跑一次 `npm run check` + `npm run build`

6. **事实可追溯**

- 每个数字、每条安全承诺都要能对应到 `README.md` / `doc/` 的具体段落；无法追溯就不写

7. **红线优先**

- 本原则与硬性红线冲突时，以红线为准

---

## 🧩 技术选型与设计约定

1. **框架与构建**

- Astro `7.x`，`output: 'static'`，`site: 'https://calmbar.<domain>'`，`trailingSlash: 'ignore'`
- 页面入口 `src/pages/index.astro`；锚点导航用原生 `#id`，不引入路由
- `tsconfig.json` 继承 `astro/tsconfigs/strict`，开启 `strict` 与 `noUncheckedIndexedAccess`

2. **Astro 集成（写死，不得替换）**

- `@astrojs/vue` `7.x`：Vue 3 单文件组件，统一 `<script setup lang="ts">`
- `@astrojs/mdx` `8.x`：长文内容载体
- `@tailwindcss/vite` `4.x`：Tailwind 以 Vite 插件接入（**不得**使用已废弃的 `@astrojs/tailwind`）

3. **Tailwind CSS v4 约定**

- 不创建 `tailwind.config.js`；主题在 `src/styles/globals.css` 用 `@import "tailwindcss"` + `@theme` 定义
- 仅允许"语义 Token + 少量布局工具类"；禁止在标签上堆砌 5 个以上原子类，复杂样式抽到组件
- shadcn-vue 需要的 `--background` / `--foreground` / `--primary` / `--border` / `--radius` 等变量在 `globals.css` 的 `@layer base` 中映射
- **必须保留 `globals.css` 顶部的 `@custom-variant data-open / data-closed / data-active / data-horizontal / data-vertical`**：生成组件大量使用 `data-open:animate-in`、`group-data-horizontal/tabs:h-9` 这类写法，Tailwind v4 不自带这些变体，删除后 Dialog / Accordion / Tabs 的动效与布局会静默失效（表现为标签页横向排成一排）
- 复杂组件（Accordion / Tabs）的收起态不要只依赖 `data-closed:animate-accordion-*`：动画结束后高度会回落为 auto，需在 `globals.css` 用 `[data-slot="accordion-content"][data-state="closed"] { height: 0 }` 兜底

4. **shadcn-vue 组件**

- 初始化：`npx shadcn-vue@latest init`，生成 `components.json`（`tsx: false`、别名 `@/components`、`@/lib/utils`）
- 工具函数 `cn()` 位于 `src/lib/utils.ts`，禁止另建第二个 class 合并工具
- 图标统一用 `@lucide/vue`（`lucide-vue-next` 已废弃，禁止使用），组件名一律带 `Icon` 后缀（`MenuIcon`、`ThermometerIcon`）
- lucide 不提供品牌图标：GitHub 标识固定复用 `src/components/site/GitHubMark.vue`，禁止再散落第二份手写 SVG
- `components.json` 基线：`style: reka-vega`、`baseColor: zinc`、`font: inter`、`iconLibrary: lucide`

5. **shadcnVue MCP 检索流程（强制）**

- 查组件是否存在：`shadcnVue_list_items_in_registries` / `shadcnVue_search_items_in_registries`（registry 用 `@shadcn`）
- 查用法示例：`shadcnVue_get_item_examples_from_registries`
- 取安装命令：`shadcnVue_get_add_command_for_items`（若返回 `[object Promise]`，以 `npx shadcn-vue@latest add <name>` 兜底）
- 生成后自检：`shadcnVue_get_audit_checklist`
- 已确认可用的 `@shadcn` 组件（编写本文件时）：`accordion` `aspect-ratio` `avatar` `badge` `button` `card` `carousel` `collapsible` `dialog` `dropdown-menu` `hover-card` `item` `kbd` `navigation-menu` `scroll-area` `separator` `sheet` `skeleton` `sonner` `tabs` `toggle-group` `tooltip`。**每次新增前仍需重新检索确认**

6. **设计风格：干净的产品官网（参考 LightC）**

- 浅色为主：页面底 `--background` 用中性浅灰，内容卡用白；不使用大面积深色 Keynote 底
- 单一品牌强调色取自旧站 Token：主色 `#0071e3`，悬停 `#0077ed`，亮色 `#2997ff`；禁止第二个强调色
- 文字层级：标题 `#1d1d1f`，正文 `#1d1d1f`，次要 `#86868b`，分隔线 `rgba(0,0,0,0.08)`
- 版面：8px 间距栅格；内容最大宽 `1200px`；圆角 `12 / 16 / 20`（`--radius` 起底）
- 克制装饰：禁止装饰性渐变、光斑、3D 插画；只用细边框、轻阴影、留白建立层级
- 进入动效（渐入）只允许两项：首屏 `.hero-enter` / `.hero-enter-media` 一次性渐入，其余版块用 `.reveal` 随滚动渐入；两者都定义在 `globals.css`，不得再新增别名动画类
- 动效实现写死为 CSS：`@supports (animation-timeline: view())` + `animation-range`，**禁止引入动画库**（GSAP / motion / AOS 等），禁止用 JS IntersectionObserver 复刻
- 动画只允许改 `opacity` 与 `transform`，时长 0.6–0.8s、位移 ≤ 18px、缓动固定 `var(--ease-reveal)`；禁止改 height/width/color 等触发布局的属性
- 必须在 `prefers-reduced-motion: reduce` 下完全不播放（`globals.css` 已用 `no-preference` 包裹），且要在浏览器不支持 scroll-driven 动画时保持静态可见
- 弹窗键盘手势（←/→ 切换、Esc 关闭）只用**单个** `window` 监听：reka 会把 `$attrs` 继续下发到内层节点，把 `@keydown` 写在 `<DialogContent>` 上会命中两层、每次按键触发两下；监听需 `watch(open)` 挂载/卸载，并在 `onBeforeUnmount` 兜底
- 字体：`-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "PingFang SC", sans-serif`；代码 `SF Mono, Menlo, monospace`

7. **版块结构契约**

| 版块         | 锚点         | 目标与内容                                                                 | 组件（shadcn-vue）                         | 内容来源                                  |
|--------------|--------------|------------------------------------------------------------------------------|--------------------------------------------|-------------------------------------------|
| 导航         | `#top`       | 品牌 + 锚点导航（功能 / 安全 / 下载 / FAQ / 关于）+ GitHub 与下载按钮          | `navigation-menu` `sheet` `button`         | —                                         |
| Hero 首屏    | `#hero`      | 版本 pill、主标题「让你的 Mac 更冷静，更从容。」、一句卖点、双 CTA、快捷键条、主控制台弹窗截图（右侧，按真实尺寸约 `300px` 宽，**不加窗口外框**） | `badge` `button` `kbd`                    | `README.md` 简介与徽章                    |
| 核心功能与界面 | `#features` | 14 项能力归并为 5 个分组，全部铺开（不用标签页）；每组标题行右侧一个带数量角标的「查看截图」按钮，截图**默认不铺在页面上**；Dialog 里按全局顺序连续翻看**全部 10 张**（每组 2 张），支持「上一张 / 下一张」+ `n / 10` 计数 + ←/→ 键（回环） | `card` `button` `dialog` | `README.md` 核心功能各节、`doc/images/`   |
| 安全边界     | `#trust`     | 4 个数字做成一条数据带 + 6 条「写在代码里的硬约束」，末尾一行带许可与版本；**不铺开成长文** | `card`                     | `README.md`、`doc/RELEASE.md`             |
| 下载         | `#download`  | 双渠道卡 + 安装与首次运行（含去隔离命令块）+ 一行系统要求；**不放源码构建、不做独立部署版块** | `card` `button` `separator`   | `README.md` 安装说明与 Releases 链接      |
| FAQ          | `#faq`       | 6 条：安装被拦截、权限需求、硬件安全、清理安全、是否联网、翻译服务端            | `accordion`                                | `src/lib/faq.ts`                          |
| 关于作者     | `#about`     | 两列：左＝作者卡片 + 链接按钮，右＝技术取舍与反馈（MDX）；下方**整行一条赞赏条**（左说明 + 右两枚 104px 白底码，点击 Dialog 放大）；末尾一行致谢徽章 | `avatar` `card` `button` `dialog` | `README.md` 致谢与仓库信息                |
|              |              | 注 1：作者头像固定用仓库内 `public/images/author-avatar.webp`（源取自 chao-eng 的 GitHub 头像，已本地化），禁止改回 `github.com/*.png` 外链 |             |                                           |
|              |              | 注 2：reka 的 `AvatarImage` 在 SSR 水合后不会补发 `load`，会给已缓存的图片留内联 `display:none`，头像永远不显示；本项目用 `SiteAvatar.vue`（`Avatar` 容器 + 原生 `img`）绕开 |             |                                           |
|              |              | 注：`avatar` 头像用 GitHub 头像地址；无法确认时用首字母占位，不得使用无关人像 |                                            |                                           |
| 页脚         | —            | 三列：品牌 + 一行授权提示、页面导航、**开源协议**（`Apache License 2.0` + 3 条权限/义务 + 「查看协议原文」外链）；底部一行版权与渠道链接 | `separator`                                | `README.md`、仓库根 `LICENSE`              |

- 页面长度预算：1440 视口下 `document.body.scrollHeight` ≤ 6000px（约 6.5 屏）。新增版块、恢复长文案或再拆出独立宣传区之前必须先确认；同类内容优先合并进现有版块，而不是新开一段

8. **内容分层与 SEO**

- 长文只留 `src/content/about-author.mdx`（作者自述），在 `.astro` 里直接 import 渲染，不走内容集合
- 其余内容全部是类型化数据：`src/lib/site.ts`（含 `SAFETY_BOUNDARIES`）、`src/lib/features.ts`（含每组截图）、`src/lib/faq.ts`
- MDX 禁止 import 第三方 npm 包或写内联脚本
- **交互容器必须 `force-mount`**：Tabs / Accordion 的非激活内容默认不渲染，会让文案从 HTML 里消失；需要 `force-mount` + 隐藏态 CSS（Tabs 用 `data-[state=inactive]:hidden`）

9. **文案与国际化**

- 首版仅简体中文 `zh-CN`；禁止引入 i18n 路由或 `astro-i18n` 类依赖
- 界面文案集中放 `src/lib/site.ts` 与 `src/content/**`，为后续多语言预留收口点

10. **响应式与无障碍**

- 断点：`sm 640` / `md 768` / `lg 1024` / `xl 1280`，移动优先；375px 宽度下不得出现横向滚动
- 语义标签优先（`header` / `nav` / `main` / `section` / `footer`），每个 `section` 带 `aria-labelledby`
- 所有图标按钮必须有 `aria-label`；图片必须写实义 `alt`（纯装饰图写 `alt=""`）
- 键盘可达，保留 `focus-visible` 焦点环；`prefers-reduced-motion` 下关闭动效

11. **性能预算**

- 首屏 JS ≤ 120KB gzip；非首屏岛屿一律 `client:visible`
- 截图统一 `webp`/`avif`，非首屏 `loading="lazy"` + `decoding="async"`；首屏主图 `loading="eager"`
- 目标：LCP ≤ 2.5s，CLS ≤ 0.1

12. **部署**

- 产物为纯静态 `dist/`，部署 Cloudflare Pages（构建 `npm run build`，输出目录 `dist`）
- 站点安全与缓存头迁移到 `web/public/_headers`（参考 `site/_headers`）
- `robots.txt` 与 `sitemap` 由 `@astrojs/sitemap` 生成，禁止手写重复文件

13. **常用命令**

```sh
npm install
npm run dev        # astro dev
npm run check      # astro check（类型与内容集合校验）
npm run build      # astro build（静态产物 dist/）
npm run preview    # astro preview
npx shadcn-vue@latest add <component>   # 组件安装，命令须先经 MCP 取得
```

---

## 📁 目录结构示例 + 错误示例对照表

### ✅ 推荐目录结构

```text
web/
├── AGENTS.md
├── astro.config.mjs          # @astrojs/vue + @astrojs/mdx + @tailwindcss/vite + sitemap
├── components.json           # shadcn-vue 配置，别名 @/components、@/lib/utils
├── package.json
├── tsconfig.json             # extends astro/tsconfigs/strict
├── public/
│   ├── _headers
│   ├── robots.txt
│   └── images/               # 由 site/images 与 doc/images 迁移并转 webp
└── src/
    ├── styles/
    │   └── globals.css       # @import "tailwindcss" + data-* 自定义变体 + @theme + shadcn 变量
    ├── lib/
    │   ├── utils.ts          # cn()
    │   ├── site.ts           # 站点常量 / 导航 / 快捷键 / 信任数据 / 安全边界 / 致谢
    │   ├── features.ts        # 功能介绍分组数据（含每组截图与图注）
    │   └── faq.ts             # FAQ 结构化数据
    ├── components/
    │   ├── ui/               # shadcn-vue 生成物，禁止手改
    │   ├── site/
    │   │   ├── SiteHeader.astro
    │   │   ├── SiteFooter.astro
    │   │   ├── MobileNav.vue        # Sheet 移动端抽屉（client:media）
    │   │   ├── LinkButton.vue       # Button + 链接的封装
    │   │   ├── SiteAvatar.vue       # Avatar 封装（带 alt）
    │   │   ├── CommandBlock.vue     # 带复制按钮的命令块（client:visible）
    │   │   ├── GitHubMark.vue       # GitHub 品牌标识（lucide 无品牌图标）
    │   │   ├── FeatureIcon.vue      # FeatureIconKey → lucide 图标
    │   │   ├── RewardCard.vue       # 赞赏码卡片 + 放大 Dialog（client:visible）
    │   └── sections/
    │       ├── HeroSection.astro
    │       ├── FeaturesSection.vue    # 功能与界面合并区（client:visible，含截图 Dialog）
    │       ├── TrustSection.astro
    │       ├── DownloadSection.astro
    │       ├── FaqSection.vue         # 手风琴（client:visible）
    │       └── AboutSection.astro
    ├── content/
    │   └── about-author.mdx         # 作者自述长文（唯一 MDX）
    └── pages/
        └── index.astro
```

### ❌ 错误示例与原因

| 错误示例                                                                        | 原因                                                                             |
|---------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| 向 `site/index.html` 写入新内容                                                 | 违反 RL-02，旧站只读，新站只在 `web/` 内建设                                      |
| FAQ 里写「支持 macOS 12.0 及以上」                                              | 违反 RL-03，`README.md` 为 macOS 14.0+                                            |
| `const props: any = Astro.props`                                                | 违反 RL-04，禁止 `any`                                                            |
| 自写 `components/sections/FaqAccordion.vue` 实现手风琴                          | 违反 RL-06，应安装 `shadcn-vue accordion`                                         |
| 新增组件前未调用 shadcnVue MCP 检索                                             | 违反 RL-05，必须先检索并取回 add 命令                                             |
| `import ElementPlus from 'element-plus'`                                        | 违反 RL-07，单一 UI 体系                                                          |
| 在 `src/components/ui/button/` 中直接改样式                                     | 违反 RL-05 / 约定 3，生成物不可改，应在包装组件覆盖                                |
| `src/stores/theme.ts` 配合 `pinia`                                              | 违反 RL-08，静态站禁状态库                                                        |
| `<ShowcaseCarousel client:load />` 用在非首屏截图区                             | 违反 RL-09，非首屏应 `client:visible`                                             |
| `style="color:#0071e3"` / `class="bg-[#0071e3]"`                                | 违反 RL-10，必须走 CSS 变量或 Token                                               |
| `<img src="../../site/images/popover_main.png">`                                | 违反 RL-02 / RL-11，资源须迁入 `web/public/images/` 并带尺寸                       |
| 在 `HeroSection.astro` 中写 `{version === '2.3.2' ? ... : ...}` 业务分支         | 违反 RL-13，逻辑应移到 `src/lib/site.ts`                                          |
| 单个 `HeroSection.astro` 写到 400 行                                            | 违反 RL-12，需拆分                                                                |
| 从 `node_modules/shadcn-vue/` 翻组件源码                                        | 违反 RL-15，用法走 MCP，生成物在 `src/components/ui/`                             |
| 手写 `<svg><path d="M3 8h11..."/></svg>` 表示风图标                             | 违反约定 4，图标用 `@lucide/vue`                                                  |
| 引入 Google Fonts 的 Inter `@import url(...)`                                   | 违反约定 6，字体用系统栈；外链字体会阻塞首屏且国内加载不稳                         |
| 在 `src/content/faq/install.mdx` 里 `import dayjs from 'dayjs'`                 | 违反约定 8，MDX 仅允许白名单组件                                                  |
| 在组件内直接写死 `https://pan.quark.cn/s/43e4bd2be8c5` 六处                     | 违反原则 4，下载地址收口到 `src/lib/site.ts`                                      |
| 改动后未跑 `npm run check` / `npm run build`                                    | 违反 RL-14                                                                        |
| 删掉或改写 `globals.css` 里的 `data-open` / `data-closed` / `data-horizontal` 等自定义变体 | 违反约定 3，Dialog 动效与 Tabs 布局会静默失效（标签页横排成一列）                   |
| Tabs / Accordion 用了 `force-mount` 但不给非激活内容加隐藏态 CSS                 | 违反约定 8，所有面板会同时铺开或全部答案可见                                       |
| 给菜单栏弹窗截图套窗口外框、或放大到 500px 以上                                  | 违反约定 7，弹窗本身很小且不是独立窗口，Hero 应呈现真实尺寸约 300px 宽               |
| 引入 GSAP / motion / AOS 或自写 IntersectionObserver 做渐入                       | 违反约定 6，渐入统一用 `globals.css` 的 `.reveal`（CSS scroll-driven，零 JS）        |
| 动画里改 height / width / filter / color                                        | 违反约定 6，只允许 `opacity` + `transform`，否则触发布局与重绘                       |
| 把 `.reveal` 加在 `position: sticky` 或 `overflow: hidden` 容器上                 | 违反约定 6，`view()` 时间轴在裁剪容器内会算错进度，元素可能停在半透明                |
| 又新开一个独立「界面预览 / 功能演示」版块                                        | 违反约定 7，截图必须并进对应功能分组，同类内容不新开一段                            |
| Hero 副标题堆 10 项功能名、功能卡描述写到 3 行                                    | 违反约定 7 的长度预算，副标题 ≤ 6 项、每个功能描述 1 行                             |
| 把安全边界铺成 9 条长文卡片、致谢排成 6 宫格                                      | 违反约定 7，信任区=数据带+6 条硬约束，致谢=一行徽章                                 |
| 把功能截图常驻铺在每个分组右侧、做成 300px 窄条                                    | 违反约定 7，截图默认收起，只留「查看截图」按钮 + Dialog 放大查看                     |
| 在 `.vue` 里 import `.astro` 组件（如 `FeatureIcon.astro`）                        | 违反约定 2，Astro 组件不能进 Vue；图标映射改写 `FeatureIcon.vue`                    |
| 赞赏码走外链、或用 `q ≤ 90` 压缩、或放在深色/透明底上                              | 违反约定 7，收款码必须是本地 `public/images/reward-*.webp`、`q ≥ 95`、白底展示，否则扫不出 |
| 把赞赏卡提到首屏、下载区或页脚顶部                                                 | 违反约定 7，赞赏只出现在 `#about` 作者区，不占用首屏与转化路径                       |
| 把赞赏卡塞进 `#about` 某一列（会让左右列高度失衡、右下留大片空白）                   | 违反约定 7，赞赏是 About 网格下方的整行横条，缩略图固定 104px 见方                    |
| 截图 Dialog 只能看一张、或只在当前分组内翻页                                      | 违反约定 7，Dialog 按全局顺序连续翻看全部 10 张，计数为 `n / 10`                     |
| 每组只配 1 张截图、漏掉电池 / 剪贴板 / 翻译 / 去隔离                               | 违反约定 7，5 个分组各配 2 张，共 10 张，截图集合见 `src/lib/features.ts`             |
| 对外声称的协议与仓库实际不符（链接指向不存在的 `LICENSE`）                          | 违反 RL-03 / 约定 7，协议信息必须与仓库根 `LICENSE` 一致，官网链接要指向它            |
| 把 `@keydown` 绑在 `<DialogContent>` 上做翻页                                     | 违反约定 6，reka 会二次下发 attrs，一次按键翻两页；必须用单个 window 监听            |
| 头像写 `https://github.com/chao-eng.png` 等外链                                   | 违反约定 7，头像必须用本地 `author-avatar.webp`，避免国内加载不稳与额外外部请求      |
