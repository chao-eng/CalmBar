export interface FaqItem {
  id: string
  question: string
  answer: string
}

export const FAQ_ITEMS: FaqItem[] = [
  {
    id: 'gatekeeper',
    question: '首次打开提示“应用程序已损坏，无法打开”怎么办？',
    answer:
      '这是 Gatekeeper 对未公证应用的拦截，不是文件损坏。确认安装包来自官方渠道后，在终端执行：\nsudo xattr -rd com.apple.quarantine /Applications/CalmBar.app\n应用内的「应用去隔离」工具也支持把任意 App 拖进去一键修复。',
  },
  {
    id: 'permissions',
    question: '需要哪些系统权限？分别用在哪里？',
    answer:
      '辅助功能用于全局快捷键与鼠标滚轮拦截；屏幕录制用于选区识字；完全磁盘访问用于卸载与缓存扫描；特权助手用于处理 /Applications 下需要管理员权限的修复。偏好设置里的「权限安全」看板逐项说明了用途，授权返回后自动刷新。',
  },
  {
    id: 'hardware-safety',
    question: '风扇调速和充电上限会不会损伤硬件？',
    answer:
      '不会。温控在退出、重启、休眠或崩溃时都会自动把 SMC 控制权交还 macOS 官方固件；充电在电量低于 15% 或电芯温度过高时强制恢复，另有底层看门狗兜底。两者都只接管官方已开放的 SMC 寄存器，不修改固件。',
  },
  {
    id: 'cleanup-safety',
    question: '清理会不会误删我的文件或聊天记录？',
    answer:
      '不会。清理统一移入系统废纸篓，误删可直接放回，且需要你逐项勾选，应用不会自动全选；不认识或不明确安全的项目不会被清理，清理范围也不涉及聊天记录数据库。',
  },
  {
    id: 'privacy',
    question: 'CalmBar 会联网上传我的数据吗？',
    answer:
      '不会。本体零远程外联，屏幕识字与剪贴板 OCR 全部跑在本机 Vision 框架上。只有你主动使用 AI 划词翻译时，才会向你自行填写的翻译端点发送待翻译文本。',
  },
  {
    id: 'translation-server',
    question: 'AI 划词翻译的服务端怎么配置？',
    answer:
      '翻译走纯 HTTP 的 OpenAI 兼容协议，端点由你自己填写。macOS 可用 MLX 硬件加速部署 Hy-MT2-1.8B（显存按需加载、空闲释放），其他系统可用 Docker 运行 llama-server 的 GGUF 量化模型。在「智能翻译」中填入 API 地址（本地为 http://127.0.0.1:8000/v1）并测试连接即可。',
  },
]
