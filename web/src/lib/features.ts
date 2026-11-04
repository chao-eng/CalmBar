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
  | 'audio'
  | 'video'
  | 'trash'
  | 'shield'
  | 'lock'
  | 'settings'
  | 'rocket'

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
}

export const FEATURE_GROUPS: FeatureGroup[] = [
  {
    id: 'thermal-battery',
    label: '散热与续航',
    summary: '风扇怎么转、电池充到多少，都在设置里写死，机器不用一直顶着高温跑。',
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
  },
  {
    id: 'efficiency',
    label: '效率与输入',
    summary: '每天要碰的键盘、菜单栏、鼠标和剪贴板，都放进同一个面板。',
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
  },
  {
    id: 'focus',
    label: '专注与拦截',
    summary: '长任务跑着，屏幕不该睡过去。误触播放键，也不该跳出不想用的播放器。',
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
  },
  {
    id: 'extraction',
    label: '信息提取',
    summary: '屏幕上的字、网页里的段落，选中就能识字或翻译。识别在本机完成，翻译只把你选中的那段发出去。',
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
  },
  {
    id: 'audio-recording',
    label: '声音与录制',
    summary: '单个应用的音量可以单独调，整块屏幕也能录下来，系统声音和麦克风分开存。',
    items: [
      {
        icon: 'audio',
        title: '按应用音频控制',
        description: '面板与混音窗口按应用调节音量、静音与输出设备，支持音量增强与路由回退。',
      },
      {
        icon: 'video',
        title: '屏幕录制与音频分轨',
        description: '全屏 / 区域 / 窗口三档录制，系统声音与麦克风独立音轨，异常退出可恢复分片。',
      },
    ],
  },
  {
    id: 'system',
    label: '系统维护',
    summary: '卸载时连同 Library 里的残留一起扫，启动项和后台服务摊开给人看。系统核心项只读，删掉的东西先进废纸篓。',
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
        icon: 'rocket',
        title: '启动项与常驻服务管理',
        description: '纳管 launchd 自启项与守护服务，崩溃告警、端口透视与快照回滚，系统核心项只读。',
      },
      {
        icon: 'settings',
        title: '通用设置与快捷键',
        description: '静默自启、菜单栏温度指示、磁贴自定义与 8 组全局快捷键。',
      },
    ],
  },
]
