export interface NavItem {
  label: string
  href: string
}

export interface Shortcut {
  keys: string[]
  name: string
  description: string
}

export interface TrustStat {
  value: string
  label: string
  hint: string
}

export interface ProblemItem {
  icon: string
  title: string
  body: string
}

export interface StackItem {
  label: string
  detail: string
}

export interface DownloadOption {
  label: string
  href: string
}

export interface DownloadChannel {
  id: string
  tag: string
  title: string
  description: string
  note: string
  variant: 'default' | 'outline'
  icon: 'download' | 'github'
  options: DownloadOption[]
}

export interface Acknowledgement {
  name: string
  url: string
}

export interface AuthorProfile {
  name: string
  avatar: string
  repoLabel: string
  intro: string
  links: { label: string; href: string }[]
}

export const SITE = {
  name: '檐下',
  latinName: 'CalmBar',
  domain: 'calmbar.bujic.cc',
  locale: 'zh-CN',
  title: '檐下 CalmBar — 常驻菜单栏的 macOS 工具集 | 让 Mac 更冷静、更从容',
  description:
    '檐下（CalmBar）是一个用 Swift 6 原生开发的 macOS 菜单栏工具集：硬件温控与风扇调速、菜单栏收纳、鼠标滚轮解耦、媒体启动拦截、防休眠防离开、80% 电池上限、剪贴板历史、离线 OCR 识字、AI 划词翻译、按应用音频控制、屏幕录制、局域网文件互传、应用深度卸载与开发者缓存清理、启动项与常驻服务管理。Apache 2.0 开源，除翻译外不发起任何外网请求。',
  keywords:
    '檐下,CalmBar,macOS 增强,菜单栏管理,Mac 风扇控制,电池 80% 保护,开发者清理,启动项管理,launchd 自启项,macOS OCR,noTunes,Gatekeeper 去隔离,AI 划词翻译,macOS 音频控制,按应用音量,屏幕录制,局域网互传,手机传文件到 Mac,网页传文件',
  version: 'v2.8.1',
  license: 'Apache License 2.0',
  tagline: '十七项能力，收进一个菜单栏图标',
  subheadline:
    '散热、充电、剪贴板、录屏、互传、清理，这些散落在系统各处的小事，收进菜单栏下方的一个面板。全部走系统原生框架，不装内核扩展，除翻译外不发起任何外网请求。',
  specs: ['Swift 6 原生', 'M1–M4 与 Intel', '除翻译外零外联'],
  osRequirement: 'macOS 14.0 (Sonoma) 或更高版本',
  archRequirement: 'Apple M1 / M2 / M3 / M4 系列及 Intel Mac',
  repo: 'https://github.com/chao-eng/CalmBar',
  releases: 'https://github.com/chao-eng/CalmBar/releases',
  issues: 'https://github.com/chao-eng/CalmBar/issues',
  licenseUrl: 'https://github.com/chao-eng/CalmBar/blob/main/LICENSE',
  downloadURL: 'https://downloads.bujic.cc/calmbar/CalmBar-2.8.1.dmg',
  translationSkill:
    'https://www.workbuddy.cn/share/asset?shareCode=8wtnv3dJoZNiwKeKsq938Y&sig=Z5OOkod-aNdJY35U',
} as const

export const NAV_ITEMS: NavItem[] = [
  { label: '核心功能', href: '#features' },
  { label: '面板一览', href: '#preview' },
  { label: '安全边界', href: '#trust' },
  { label: '下载', href: '#download' },
  { label: '常见问题', href: '#faq' },
  { label: '关于作者', href: '#about' },
]

export const HERO_STATS: TrustStat[] = [
  { value: '17', label: '项能力', hint: '收进同一个菜单栏面板' },
  { value: '8', label: '组全局快捷键', hint: '面板、翻译、识字、录屏' },
  { value: '24+', label: '款工具链清理', hint: 'Xcode、Node、Python、Rust…' },
  { value: '0', label: '内核扩展', hint: '只调用系统原生框架' },
]

export const PROBLEMS: ProblemItem[] = [
  {
    icon: 'thermometer',
    title: '风扇要么狂转，要么不动',
    body: '编译时烫手，闲时也在转。系统只给「自动」一档，看不到具体温度，也没有手动曲线。',
  },
  {
    icon: 'battery',
    title: '电池长期插着充满',
    body: '一直 100% 挂着电源，电芯化学年龄掉得比循环次数快，等发现时已经换不回来了。',
  },
  {
    icon: 'menu',
    title: '菜单栏图标挤成一排',
    body: '常驻图标越装越多，右侧被挤到换行，低频的那几个又不敢卸载。',
  },
  {
    icon: 'trash',
    title: '卸载只删了 .app',
    body: 'Library 里留一堆缓存和容器，开发缓存越攒越大，系统设置里还挂着一堆失效自启项。',
  },
]

export const STACK: StackItem[] = [
  { label: 'Swift 6', detail: '并发检查全开' },
  { label: 'SwiftUI', detail: '面板与设置页' },
  { label: 'AppKit', detail: '状态栏与窗口' },
  { label: 'SMC', detail: '温度与风扇读写' },
  { label: 'IOKit', detail: '电源断言' },
  { label: 'Vision', detail: '离线文字识别' },
]

export const SHORTCUTS: Shortcut[] = [
  { keys: ['⌥', '⌘', 'K'], name: '全局命令面板', description: '拼音首字母模糊匹配，回车即执行' },
  { keys: ['⌥', '⌘', 'H'], name: '菜单栏一键折叠', description: '收纳或展开隐藏图标区域' },
  { keys: ['⌥', '⌘', 'T'], name: 'AI 翻译剪贴板', description: '读取剪贴板文本就地流式翻译' },
  { keys: ['⌘', 'C', '×2'], name: '划词就地翻译', description: '连按两次复制，在光标旁弹出译文' },
  { keys: ['⌥', '⌘', 'O'], name: '屏幕选区识字', description: '框选屏幕区域离线提取文字' },
  { keys: ['⌥', '⌘', 'V'], name: '剪贴板历史', description: '快速检索并粘贴历史记录' },
  { keys: ['⌥', '⌘', 'R'], name: '屏幕录制', description: '开始或停止全屏 / 区域 / 窗口录制' },
  { keys: ['⌥', '⌘', 'F'], name: '打开录制文件夹', description: '在访达中定位已保存的录制文件' },
]

export const TRUST_STATS: TrustStat[] = [
  { value: '约 10MB', label: '双架构通用安装包', hint: 'Apple 芯片与 Intel 同一个 DMG' },
  { value: '100%', label: '本地离线运行', hint: '识字与 OCR 全在本机' },
  { value: '0', label: '内核扩展', hint: '不修改固件与系统文件' },
  { value: '30 天', label: '自启项快照保留', hint: '误删可无损还原' },
]

export const DOWNLOAD_CHANNELS: DownloadChannel[] = [
  {
    id: 'cloudflare',
    tag: '国内直连',
    title: 'Cloudflare 直链下载',
    description: '一个 DMG，Apple 芯片和 Intel 都能装，版本跟仓库同步。',
    note: '无需登录，下载更稳定',
    variant: 'default',
    icon: 'download',
    options: [{ label: '下载通用 DMG 安装包', href: SITE.downloadURL }],
  },
  {
    id: 'github',
    tag: '官方开源仓库',
    title: 'GitHub Releases 与源码',
    description: '想核对版本号，或者翻源码，从这里进。',
    note: '支持 Star 与 Issue 反馈',
    variant: 'outline',
    icon: 'github',
    options: [{ label: '访问 GitHub 仓库', href: SITE.repo }],
  },
]

export const ACKNOWLEDGEMENTS: Acknowledgement[] = [
  { name: 'Pearcleaner', url: 'https://github.com/alienator88/Pearcleaner' },
  { name: 'Aidente', url: 'https://github.com/aidente' },
  { name: 'noTunes', url: 'https://github.com/tombonez/noTunes' },
  { name: 'Hidden Bar', url: 'https://github.com/dwarvesf/hidden' },
]

export const AUTHOR: AuthorProfile = {
  name: 'chao-eng',
  avatar: '/images/author-avatar.webp',
  repoLabel: 'github.com/chao-eng/CalmBar',
  intro:
    '檐下是一个个人开源项目，功能取舍只服务于一件事：让 Mac 用起来更冷静、更干净。',
  links: [
    { label: 'GitHub 仓库', href: SITE.repo },
    { label: '提交 Issue', href: SITE.issues },
    { label: '开源协议', href: SITE.licenseUrl },
  ],
}

export interface RewardCode {
  id: string
  label: string
  src: string
  width: number
  height: number
  alt: string
}

export const REWARD_NOTE =
  '檐下以 Apache License 2.0 开源，免费使用。如果它确实帮到了你，可以随意赞赏一点，不赞赏也完全不影响使用。'

export const REWARD_CODES: RewardCode[] = [
  {
    id: 'wechat',
    label: '微信赞赏',
    src: '/images/reward-wechat.webp',
    width: 480,
    height: 478,
    alt: '檐下作者的微信赞赏码',
  },
  {
    id: 'alipay',
    label: '支付宝',
    src: '/images/reward-alipay.webp',
    width: 560,
    height: 560,
    alt: '檐下作者的支付宝收款码',
  },
]

export const INSTALL_COMMAND = `xattr -dr com.apple.quarantine ~/Downloads/CalmBar-${SITE.version.replace(/^v/, '')}.dmg`

export const SAFETY_BOUNDARIES = [
  '温控在退出、重启、休眠或崩溃时自动交还 SMC 官方托管',
  '电量低于 15% 或电芯温度过高时强制恢复充电',
  '只接管官方已开放的 SMC 寄存器，不修改固件',
  '清理统一移入系统废纸篓，且必须逐项勾选，不自动全选',
  '识别全部在本地 Vision 完成，图片与文字不出本机',
  '局域网互传默认关闭，只在所选网段内监听，不经过任何外部服务器',
  '仅翻译时向你自己填写的端点发送文本，其余零外联',
]
