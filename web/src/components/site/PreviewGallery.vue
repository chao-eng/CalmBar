<script setup lang="ts">
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Badge } from '@/components/ui/badge'

interface Shot {
  id: string
  label: string
  title: string
  desc: string
  src: string
  height: number
  points: string[]
}

const shots: Shot[] = [
  {
    id: 'thermal',
    label: '温控',
    title: '硬件温控',
    desc: 'CPU / GPU / 电池 / SoC 温度一屏读完，风扇支持自动、手动与智能曲线三档，双风扇可联动或独立调速。',
    src: '/images/screenshots/thermal.webp',
    height: 768,
    points: [
      '自动 / 自定义 / 智能曲线三种策略随时切换',
      '双风扇可联动，也能各自给一条曲线',
      '退出、休眠或崩溃时自动把 SMC 控制权交还系统',
    ],
  },
  {
    id: 'manage',
    label: '守护',
    title: '守护分区',
    desc: '充电上限、防休眠、菜单栏收纳与滚轮方向解耦，都是长驻型开关，状态写在入口上，点开才展开细节。',
    src: '/images/screenshots/manage.webp',
    height: 872,
    points: [
      '充电上限 70%~100% 可选，回差巡航减少边缘反复充电',
      '防休眠用电源断言，同时给协同办公软件发 HID 微动',
      '菜单栏收纳按住 ⌘ 拖入即可，⌥⌘H 一键折叠',
    ],
  },
  {
    id: 'tools',
    label: '工具',
    title: '工具分区',
    desc: '屏幕录制、截屏识字、AI 翻译、清理与互传，高频动作集中在一处，磁贴可以按自己的习惯重新排序。',
    src: '/images/screenshots/tools.webp',
    height: 728,
    points: [
      '每个磁贴都带自己的快捷键，不用先开面板',
      '互传打开后本机起一个网页，同一 Wi-Fi 直接互发',
      '清理中心把库残留与开发缓存分开列出，逐项勾选',
    ],
  },
  {
    id: 'monitor',
    label: '监控',
    title: '系统监控',
    desc: '温度、负载、内存与磁盘的实时读数，超过阈值才提醒，不做常驻弹窗。',
    src: '/images/screenshots/monitor.webp',
    height: 972,
    points: [
      '采样在后台线程完成，不阻塞面板交互',
      '温度异常先提醒再降频，不静默接管风扇',
      '菜单栏可以只显示一个温度读数',
    ],
  },
  {
    id: 'sound',
    label: '声音',
    title: '音频控制',
    desc: '按应用单独调音量、静音与切换输出设备，支持超过 100% 的增益；系统提示音与通话音频始终不接管。',
    src: '/images/screenshots/sound.webp',
    height: 728,
    points: [
      '按应用聚合所有关联进程，不会只调到一个子进程',
      '音量范围 0~200%，变更走增益平滑过渡',
      '受保护音频与通话始终走系统默认',
    ],
  },
]
</script>

<template>
  <div class="flex flex-col gap-5">
    <Tabs default-value="thermal" class="w-full min-w-0 gap-5">
      <div class="no-scrollbar w-full min-w-0 overflow-x-auto">
        <TabsList variant="line" class="h-9 w-max justify-start">
          <TabsTrigger
            v-for="shot in shots"
            :key="shot.id"
            :value="shot.id"
            class="shrink-0 px-3 text-sm"
          >
            {{ shot.label }}
          </TabsTrigger>
        </TabsList>
      </div>

      <TabsContent
        v-for="shot in shots"
        :key="shot.id"
        :value="shot.id"
        force-mount
        class="mt-0 outline-none data-[state=inactive]:hidden"
      >
        <div class="grid items-start gap-6 md:grid-cols-[minmax(0,280px)_minmax(0,1fr)] md:gap-10">
          <figure class="panel-frame mx-auto w-full max-w-[300px]">
            <div class="border-border/70 flex items-center gap-2 border-b px-3 py-2">
              <span class="flex gap-1.5" aria-hidden="true">
                <span class="size-2.5 rounded-full bg-mac-close"></span>
                <span class="size-2.5 rounded-full bg-mac-minimize"></span>
                <span class="size-2.5 rounded-full bg-mac-zoom"></span>
              </span>
              <span class="text-muted-foreground ml-1 truncate font-mono text-[0.7rem]">
                檐下 · {{ shot.title }}
              </span>
            </div>
            <img
              :src="shot.src"
              :alt="`檐下菜单栏面板的${shot.title}分区`"
              width="640"
              :height="shot.height"
              loading="lazy"
              decoding="async"
              class="bg-muted/40 block h-auto w-full"
            />
          </figure>

          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h3 class="text-lg font-semibold tracking-tight">{{ shot.title }}</h3>
              <Badge variant="secondary" class="h-5 text-[0.68rem]">真实截图</Badge>
            </div>
            <p class="text-muted-foreground mt-2 text-sm leading-7">{{ shot.desc }}</p>

            <ul class="mt-4 flex flex-col gap-2.5">
              <li
                v-for="point in shot.points"
                :key="point"
                class="text-muted-foreground flex gap-3 text-sm leading-6"
              >
                <span class="bg-primary mt-2 size-1.5 shrink-0 rounded-full" />
                <span>{{ point }}</span>
              </li>
            </ul>
          </div>
        </div>
      </TabsContent>
    </Tabs>
  </div>
</template>
