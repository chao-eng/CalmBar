export interface Shot {
  src: string
  width: number
  height: number
  caption: string
  alt: string
}

export type FeatureIconKey =
  | 'thermometer'
  | 'battery'
  | 'command'
  | 'menu'
  | 'mouse'
  | 'clipboard'
  | 'coffee'
  | 'music'
  | 'scan'
  | 'languages'
  | 'trash'
  | 'shield'
  | 'lock'
  | 'settings'

export interface FeatureItem {
  icon: FeatureIconKey
  title: string
  description: string
}

export interface FeatureGroup {
  id: string
  label: string
  summary: string
  items: FeatureItem[]
  shots: Shot[]
}

export const FEATURE_GROUPS: FeatureGroup[] = [
  {
    id: 'thermal-battery',
    label: '散热与续航',
    summary: '风扇曲线与充电阈值握在自己手里，让机器长期待在舒适区间。',
    items: [
      {
        icon: 'thermometer',
        title: '硬件监控与智能温控',
        description: 'CPU / GPU / SoC 实时温度，自动、手动、智能曲线三档，双风扇可联动或独立控制。',
      },
      {
        icon: 'battery',
        title: '80% 充电上限与回差巡航',
        description: 'SMC 写入充电阈值，达标后转旁路供电；低于 15% 或温度过高自动熔断。',
      },
    ],
    shots: [
      {
        src: '/images/thermal_settings.webp',
        width: 1536,
        height: 1280,
        caption: '硬件温控与智能曲线',
        alt: '硬件温控偏好设置，包含智能加速曲线与各核心温度读数',
      },
      {
        src: '/images/battery_settings.webp',
        width: 1624,
        height: 1368,
        caption: '充电上限与电池健康',
        alt: '充电管理设置，包含充电上限、回差巡航与电池健康度读数',
      },
    ],
  },
  {
    id: 'efficiency',
    label: '效率与输入',
    summary: '键盘、菜单栏、鼠标、剪贴板，四个高频入口一次收拢。',
    items: [
      {
        icon: 'command',
        title: 'Command Palette 命令面板',
        description: '⌥⌘K 唤出，支持中英文与拼音首字母模糊匹配，回车即执行。',
      },
      {
        icon: 'menu',
        title: '菜单栏图标收纳',
        description: '按住 ⌘ 拖入低频图标，⌥⌘H 一键折叠，支持悬停自动展开。',
      },
      {
        icon: 'mouse',
        title: '外接鼠标滚动解耦',
        description: '外接鼠标反转垂直滚动，内建触控板保持原生自然方向与惯性。',
      },
      {
        icon: 'clipboard',
        title: '剪贴板历史记录',
        description: '文本、图片、链接、文件全格式捕获，图片自动建立 OCR 索引。',
      },
    ],
    shots: [
      {
        src: '/images/command_palette.webp',
        width: 1252,
        height: 892,
        caption: 'Command Palette 命令面板',
        alt: 'Command Palette 命令面板搜索界面',
      },
      {
        src: '/images/clipboard_history.webp',
        width: 1264,
        height: 1240,
        caption: '剪贴板历史记录',
        alt: '剪贴板历史记录窗口，支持按文本、图片、链接、文件筛选',
      },
    ],
  },
  {
    id: 'focus',
    label: '专注与拦截',
    summary: '长任务不被打断，误触播放键也不再弹出不想用的播放器。',
    items: [
      {
        icon: 'coffee',
        title: '防休眠与防离开判定',
        description: 'IOKit 电源断言阻止休眠，HID 微动降低协同办公软件的离开判定。',
      },
      {
        icon: 'music',
        title: 'Apple Music 启动拦截',
        description: '拦截 Music 自动唤起，可改为拉起 Spotify、网易云音乐或网页播放器。',
      },
    ],
    shots: [
      {
        src: '/images/caffeine_settings.webp',
        width: 1624,
        height: 1368,
        caption: '防休眠与防离开判定',
        alt: '防休眠设置，包含定时保持与办公软件防离开判定开关',
      },
      {
        src: '/images/notunes_settings.webp',
        width: 1624,
        height: 1368,
        caption: '音乐拦截与替代启动',
        alt: '音乐拦截与替代启动设置界面',
      },
    ],
  },
  {
    id: 'extraction',
    label: '信息提取',
    summary: '屏幕上的文字与网页里的段落，就地识别、就地翻译。',
    items: [
      {
        icon: 'scan',
        title: '离线屏幕识字',
        description: 'Vision 框架框选识字，自动中英混排与二维码解析，结果自动复制。',
      },
      {
        icon: 'languages',
        title: 'AI 划词翻译',
        description: '双击 ⌘C 或按 ⌥⌘T 就地弹出流式译文，覆盖 38 种语言体系。',
      },
    ],
    shots: [
      {
        src: '/images/ocr_settings.webp',
        width: 1624,
        height: 1368,
        caption: '屏幕识字与二维码解析',
        alt: '屏幕文字识别偏好设置界面',
      },
      {
        src: '/images/translation_floating.webp',
        width: 492,
        height: 446,
        caption: '划词翻译悬浮浮窗',
        alt: 'AI 划词翻译的毛玻璃悬浮结果浮窗',
      },
    ],
  },
  {
    id: 'disk-security',
    label: '磁盘与权限',
    summary: '清理要清得干净，越界的事一件都不做。',
    items: [
      {
        icon: 'trash',
        title: '应用卸载与开发者清理',
        description: '扫描 Library 残留，覆盖 24+ 款工具链缓存与已成孤儿的 IDE 工作区。',
      },
      {
        icon: 'shield',
        title: '去隔离与签名修复',
        description: '拖拽即递归剥离隔离属性，可选 Ad-hoc 重签名，免反复输入 sudo。',
      },
      {
        icon: 'lock',
        title: '统一权限看板',
        description: '辅助功能、屏幕录制、完全磁盘访问与助手状态一屏可查。',
      },
      {
        icon: 'settings',
        title: '通用设置与快捷键',
        description: '静默自启、菜单栏温度指示、磁贴自定义与 6 组全局快捷键。',
      },
    ],
    shots: [
      {
        src: '/images/cleaner_developer.webp',
        width: 1784,
        height: 1320,
        caption: '开发者缓存清理',
        alt: '开发者工具链缓存清理界面',
      },
      {
        src: '/images/gatekeeper_unlocker.webp',
        width: 1624,
        height: 1368,
        caption: '应用去隔离与权限看板',
        alt: '应用去隔离与自签名修复界面',
      },
    ],
  },
]
