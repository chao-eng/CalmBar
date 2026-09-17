<script setup lang="ts">
import type { HTMLAttributes } from 'vue'
import { Avatar } from '@/components/ui/avatar'

const props = defineProps<{
  src: string
  alt: string
  class?: HTMLAttributes['class']
}>()
</script>

<template>
  <Avatar :class="props.class">
    <img
      :src="props.src"
      :alt="props.alt"
      width="160"
      height="160"
      class="size-full rounded-full bg-muted object-cover"
    />
  </Avatar>
</template>
