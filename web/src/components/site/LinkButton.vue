<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import type { ButtonVariants } from '@/components/ui/button'
import { Button } from '@/components/ui/button'

const props = withDefaults(defineProps<{
  href: string
  variant?: ButtonVariants['variant']
  size?: ButtonVariants['size']
  external?: boolean
  class?: HTMLAttributes['class']
}>(), {
  external: false,
})
</script>

<template>
  <Button
    as="a"
    :href="props.href"
    :variant="props.variant"
    :size="props.size"
    :target="props.external ? '_blank' : undefined"
    :rel="props.external ? 'noopener noreferrer' : undefined"
    :class="props.class"
  >
    <slot />
  </Button>
</template>
