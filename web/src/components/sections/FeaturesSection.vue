<script setup lang="ts">
import { ArrowUpRightIcon, ChevronLeftIcon, ChevronRightIcon, ImageIcon } from '@lucide/vue'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog'
import FeatureIcon from '@/components/site/FeatureIcon.vue'
import type { Shot } from '@/lib/features'
import { FEATURE_GROUPS } from '@/lib/features'

interface GalleryItem {
  groupLabel: string
  shot: Shot
}

const gallery = computed<GalleryItem[]>(() =>
  FEATURE_GROUPS.flatMap((group) =>
    group.shots.map((shot) => ({ groupLabel: group.label, shot })),
  ),
)

const groupStarts = computed(() => {
  let offset = 0
  return FEATURE_GROUPS.map((group) => {
    const start = offset
    offset += group.shots.length
    return start
  })
})

const total = computed(() => gallery.value.length)
const index = ref(0)
const open = ref(false)

const active = computed<GalleryItem>(
  () => gallery.value[index.value] ?? gallery.value[0]!,
)

function show(start: number) {
  index.value = start
  open.value = true
}

function step(offset: number) {
  index.value = (index.value + offset + total.value) % total.value
}

function onKeydown(event: KeyboardEvent) {
  if (event.key === 'ArrowLeft') {
    event.preventDefault()
    step(-1)
  }
  else if (event.key === 'ArrowRight') {
    event.preventDefault()
    step(1)
  }
}

watch(open, (visible) => {
  if (visible)
    window.addEventListener('keydown', onKeydown)
  else
    window.removeEventListener('keydown', onKeydown)
})

onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))
</script>

<template>
  <section id="features" class="section" aria-labelledby="features-title">
    <div class="container-page">
      <div class="reveal mx-auto max-w-2xl text-center">
        <p class="section-eyebrow">
          核心功能与界面
        </p>
        <h2 id="features-title" class="section-title mt-2">
          十四项能力，收进一个菜单栏图标
        </h2>
        <p class="section-desc">
          按使用场景分成五组。每组的真实界面截图默认收起，点击「查看截图」可放大并连续翻看全部截图。
        </p>
      </div>

      <div class="mt-9 space-y-6">
        <div
          v-for="(group, i) in FEATURE_GROUPS"
          :key="group.id"
          class="reveal border-t border-border pt-6"
        >
          <div class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-2">
            <div>
              <h3 class="text-lg font-semibold tracking-tight">
                {{ group.label }}
              </h3>
              <p class="mt-1.5 text-sm leading-relaxed text-muted-foreground">
                {{ group.summary }}
              </p>
            </div>

            <Button
              variant="outline"
              size="sm"
              :aria-label="`查看${group.label}的界面截图`"
              @click="show(groupStarts[i] ?? 0)"
            >
              <ImageIcon />
              查看截图
              <span class="text-muted-foreground">{{ group.shots.length }}</span>
            </Button>
          </div>

          <ul class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <li
              v-for="item in group.items"
              :key="item.title"
              class="flex gap-2.5 rounded-lg border border-border bg-card p-3"
            >
              <span class="flex size-7 shrink-0 items-center justify-center rounded-md bg-primary/10 text-primary">
                <FeatureIcon :name="item.icon" class="size-3.5" />
              </span>
              <span class="min-w-0">
                <span class="block text-sm font-medium">{{ item.title }}</span>
                <span class="mt-0.5 block text-xs leading-relaxed text-muted-foreground">
                  {{ item.description }}
                </span>
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>

    <Dialog v-model:open="open">
      <DialogContent class="max-h-[92vh] max-w-[calc(100%-2rem)] overflow-y-auto sm:max-w-4xl">
        <DialogTitle class="pr-8 text-base font-medium">
          {{ active.groupLabel }} · {{ active.shot.caption }}
        </DialogTitle>
        <DialogDescription class="sr-only">
          {{ active.shot.alt }}
        </DialogDescription>

        <img
          :src="active.shot.src"
          :width="active.shot.width"
          :height="active.shot.height"
          :alt="active.shot.alt"
          class="w-full rounded-lg border border-border bg-card"
        />

        <div class="flex items-center justify-between gap-3">
          <Button variant="outline" size="sm" aria-label="上一张截图" @click="step(-1)">
            <ChevronLeftIcon />
            上一张
          </Button>
          <span class="text-xs text-muted-foreground">{{ index + 1 }} / {{ total }}</span>
          <Button variant="outline" size="sm" aria-label="下一张截图" @click="step(1)">
            下一张
            <ChevronRightIcon data-icon="inline-end" />
          </Button>
        </div>

        <a
          :href="active.shot.src"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowUpRightIcon class="size-3.5" />
          在新标签页打开原图
        </a>
      </DialogContent>
    </Dialog>
  </section>
</template>
