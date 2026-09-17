<script setup lang="ts">
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { FAQ_ITEMS } from '@/lib/faq'

interface Segment {
  text: string
  mono: boolean
}

function toSegments(answer: string): Segment[] {
  return answer
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .map((line) => ({ text: line, mono: /^(sudo|git|http)/.test(line) }))
}
</script>

<template>
  <section id="faq" class="section border-y border-border bg-card" aria-labelledby="faq-title">
    <div class="container-page">
      <div class="reveal mx-auto max-w-2xl text-center">
        <p class="section-eyebrow">
          常见问题
        </p>
        <h2 id="faq-title" class="section-title mt-2">
          装之前想知道的，基本都在这里
        </h2>
        <p class="section-desc">
          安装、权限与安全相关的疑问，先在这里找答案。
        </p>
      </div>

      <div class="reveal card-surface mx-auto mt-10 max-w-3xl px-5 sm:px-6">
        <Accordion type="single" collapsible>
          <AccordionItem v-for="item in FAQ_ITEMS" :key="item.id" :value="item.id">
            <AccordionTrigger class="text-base">
              {{ item.question }}
            </AccordionTrigger>
            <AccordionContent force-mount class="text-muted-foreground">
              <p
                v-for="segment in toSegments(item.answer)"
                :key="segment.text"
                :class="
                  segment.mono
                    ? 'mono-block mt-2 text-sm'
                    : 'leading-relaxed'
                "
              >
                {{ segment.text }}
              </p>
            </AccordionContent>
          </AccordionItem>
        </Accordion>
      </div>
    </div>
  </section>
</template>
