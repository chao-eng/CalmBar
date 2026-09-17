<script setup lang="ts">
import { CheckIcon, CopyIcon } from '@lucide/vue'
import { ref } from 'vue'
import { Button } from '@/components/ui/button'

const props = defineProps<{
  code: string
  label?: string
}>()

const copied = ref(false)

async function copy() {
  try {
    await navigator.clipboard.writeText(props.code)
    copied.value = true
    window.setTimeout(() => {
      copied.value = false
    }, 1600)
  }
  catch {
    copied.value = false
  }
}
</script>

<template>
  <div class="overflow-hidden rounded-lg border border-border bg-foreground">
    <div class="flex items-center justify-between gap-3 border-b border-white/10 px-3 py-1.5">
      <span class="text-xs text-background/70">{{ label ?? '终端命令' }}</span>
      <Button
        size="xs"
        variant="ghost"
        class="text-background/80 hover:bg-white/10 hover:text-background"
        :aria-label="copied ? '已复制到剪贴板' : '复制命令'"
        @click="copy"
      >
        <component :is="copied ? CheckIcon : CopyIcon" />
        {{ copied ? '已复制' : '复制' }}
      </Button>
    </div>
    <pre class="overflow-x-auto whitespace-pre-wrap break-words p-4 font-mono text-sm leading-relaxed text-background"><code>{{ code }}</code></pre>
  </div>
</template>
