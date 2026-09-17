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
}

export interface DownloadChannel {
  id: string
  tag: string
  title: string
  description: string
  action: string
  href: string
  note: string
  recommended: boolean
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
  name: 'CalmBar',
  domain: 'calmbar.bujic.cc',
  locale: 'zh-CN',
  title: 'CalmBar — macOS 全能系统增强套件 | 让你的 Mac 更冷静、更从容',
  description:
    'CalmBar 是一款使用 Swift 6 原生打造的 macOS 菜单栏系统增强套件：硬件温控与风扇调速、菜单栏收纳、鼠标滚轮解耦、媒体启动拦截、防休眠防离开、80% 电池上限、剪贴板历史、离线 OCR 识字、AI 划词翻译、应用深度卸载与开发者缓存清理。开源免费，纯离线零外联。',
  keywords:
    'CalmBar,macOS 增强,菜单栏管理,Mac 风扇控制,电池 80% 保护,开发者清理,macOS OCR,noTunes,Gatekeeper 去隔离,AI 划词翻译',
  version: 'v2.3.2',
  license: 'Apache License 2.0',
  subheadline:
    '硬件温控 · 菜单栏收纳 · 电池上限 · 离线识字 · AI 划词翻译 · 开发者清理',
  specs: ['Swift 6 原生', 'M1–M4 与 Intel', '纯离线零外联'],
  osRequirement: 'macOS 14.0 (Sonoma) 或更高版本',
  archRequirement: 'Apple M1 / M2 / M3 / M4 系列及 Intel Mac',
  repo: 'https://github.com/chao-eng/CalmBar',
  releases: 'https://github.com/chao-eng/CalmBar/releases',
  issues: 'https://github.com/chao-eng/CalmBar/issues',
  licenseUrl: 'https://github.com/chao-eng/CalmBar/blob/main/LICENSE',
  quarkPan: 'https://pan.quark.cn/s/43e4bd2be8c5',
} as const

export const NAV_ITEMS: NavItem[] = [
  { label: '核心功能', href: '#features' },
  { label: '安全边界', href: '#trust' },
  { label: '下载', href: '#download' },
  { label: '常见问题', href: '#faq' },
  { label: '关于作者', href: '#about' },
]

export const SHORTCUTS: Shortcut[] = [
  { keys: ['⌥', '⌘', 'K'], name: '全局命令面板', description: '拼音首字母模糊匹配，回车即执行' },
  { keys: ['⌥', '⌘', 'H'], name: '菜单栏一键折叠', description: '收纳或展开隐藏图标区域' },
  { keys: ['⌥', '⌘', 'T'], name: 'AI 翻译剪贴板', description: '读取剪贴板文本就地流式翻译' },
  { keys: ['⌘', 'C', '×2'], name: '划词就地翻译', description: '连按两次复制，在光标旁弹出译文' },
  { keys: ['⌥', '⌘', 'O'], name: '屏幕选区识字', description: '框选屏幕区域离线提取文字' },
  { keys: ['⌥', '⌘', 'V'], name: '剪贴板历史', description: '快速检索并粘贴历史记录' },
]

export const TRUST_STATS: TrustStat[] = [
  { value: '0.1%', label: '后台 CPU 占用' },
  { value: '约 10MB', label: '本体体积' },
  { value: '100%', label: '离线本地运行' },
  { value: '24+', label: '工具链清理覆盖' },
]

export const DOWNLOAD_CHANNELS: DownloadChannel[] = [
  {
    id: 'quark',
    tag: '国内直链',
    title: '夸克网盘下载',
    description: '免特殊网络环境获取 DMG，与仓库版本同步更新。',
    action: '前往夸克网盘下载',
    href: SITE.quarkPan,
    note: '国内访问更稳定',
    recommended: true,
  },
  {
    id: 'github',
    tag: '官方开源仓库',
    title: 'GitHub Releases 与源码',
    description: '获取最新 Release、核对版本号，或查看全部源码。',
    action: '访问 GitHub 仓库',
    href: SITE.repo,
    note: '支持 Star 与 Issue 反馈',
    recommended: false,
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
    'CalmBar 是一个个人开源项目，从第一行代码到发布维护都由作者独立完成，功能取舍只服务于一件事：让 Mac 用起来更冷静、更干净。',
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
  'CalmBar 以 Apache License 2.0 开源，免费使用。如果它确实帮到了你，可以随意赞赏一点 —— 不赞赏也完全不影响使用。'

export const REWARD_CODES: RewardCode[] = [
  {
    id: 'wechat',
    label: '微信赞赏',
    src: '/images/reward-wechat.webp',
    width: 480,
    height: 478,
    alt: 'CalmBar 作者的微信赞赏码',
  },
  {
    id: 'alipay',
    label: '支付宝',
    src: '/images/reward-alipay.webp',
    width: 560,
    height: 560,
    alt: 'CalmBar 作者的支付宝收款码',
  },
]

export const INSTALL_COMMAND =
  'sudo xattr -rd com.apple.quarantine /Applications/CalmBar.app'

export const SAFETY_BOUNDARIES = [
  '温控在退出、重启、休眠或崩溃时自动交还 SMC 官方托管',
  '电量低于 15% 或电芯温度过高时强制恢复充电',
  '只接管官方已开放的 SMC 寄存器，不修改固件',
  '清理统一移入系统废纸篓，且必须逐项勾选，不自动全选',
  '识别全部在本地 Vision 完成，图片与文字不出本机',
  '仅翻译时向你自己填写的端点发送文本，其余零外联',
]
