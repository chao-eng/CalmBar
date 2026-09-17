<script setup lang="ts">
import { HeartIcon } from '@lucide/vue'
import { ref } from 'vue'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/ui/dialog'
import type { RewardCode } from '@/lib/site'
import { REWARD_CODES, REWARD_NOTE } from '@/lib/site'

const active = ref<RewardCode | null>(null)
const open = ref(false)

function show(code: RewardCode) {
  active.value = code
  open.value = true
}
</script>

<template>
  <Card size="sm">
    <CardContent class="flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between sm:gap-8">
      <div class="max-w-xl">
        <h3 class="flex items-center gap-2 text-base font-medium">
          <HeartIcon class="size-4 text-primary" />
          赞赏
        </h3>
        <p class="mt-2 text-sm leading-relaxed text-muted-foreground">
          {{ REWARD_NOTE }}
        </p>
      </div>

      <div class="flex shrink-0 gap-3">
        <button
          v-for="code in REWARD_CODES"
          :key="code.id"
          type="button"
          class="group w-[104px] rounded-lg border border-border bg-card p-1.5 transition-colors hover:border-primary/40"
          :aria-label="`放大查看${code.alt}`"
          @click="show(code)"
        >
          <img
            :src="code.src"
            :width="code.width"
            :height="code.height"
            :alt="code.alt"
            loading="lazy"
            decoding="async"
            class="w-full rounded-md bg-card object-contain"
          />
          <span class="mt-1.5 block text-center text-xs font-medium">{{ code.label }}</span>
        </button>
      </div>
    </CardContent>
  </Card>

  <Dialog v-model:open="open">
    <DialogContent class="max-w-[calc(100%-2rem)] sm:max-w-lg">
      <DialogTitle class="pr-8 text-base font-medium">
        {{ active?.label ?? '赞赏' }}
      </DialogTitle>
      <DialogDescription class="sr-only">
        {{ active?.alt ?? '' }}
      </DialogDescription>

      <img
        v-if="active"
        :src="active.src"
        :width="active.width"
        :height="active.height"
        :alt="active.alt"
        class="mx-auto w-full max-w-sm rounded-lg bg-card object-contain"
      />

      <p class="text-center text-xs text-muted-foreground">长按或截图后用对应 App 扫码</p>
    </DialogContent>
  </Dialog>
</template>
