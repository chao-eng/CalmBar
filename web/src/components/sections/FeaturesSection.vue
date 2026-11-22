<script setup lang="ts">
import FeatureIcon from '@/components/site/FeatureIcon.vue'
import { FEATURE_GROUPS } from '@/lib/features'
</script>

<template>
  <section id="features" class="border-border/70 bg-muted/25 border-y" aria-labelledby="features-title">
    <div class="container-page py-14 sm:py-18 lg:py-22">
      <div class="reveal max-w-2xl">
        <p class="eyebrow">
          核心功能
        </p>
        <h2 id="features-title" class="section-title">
          十七项能力，收进一个菜单栏图标
        </h2>
        <p class="section-desc">
          六组功能，按平时用得到的地方排开。每组写清楚它管什么，边界在哪。
        </p>
      </div>

      <div class="mt-9 space-y-8">
        <div
          v-for="group in FEATURE_GROUPS"
          :key="group.id"
          class="reveal border-border/70 border-t pt-6"
        >
          <div class="flex flex-col gap-1 sm:flex-row sm:items-baseline sm:justify-between">
            <h3 class="text-lg font-semibold tracking-tight">
              {{ group.label }}
            </h3>
            <span class="text-muted-foreground font-mono text-xs">
              {{ group.items.length }} 项
            </span>
          </div>
          <p class="text-muted-foreground mt-1.5 text-sm leading-relaxed">
            {{ group.summary }}
          </p>

          <ul class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <li
              v-for="item in group.items"
              :key="item.title"
              class="ring-foreground/10 bg-card flex gap-3 rounded-xl p-4 ring-1 transition-shadow hover:shadow-sm"
            >
              <span
                class="bg-accent/60 text-primary ring-primary/10 flex size-8 shrink-0 items-center justify-center rounded-lg ring-1"
              >
                <FeatureIcon :name="item.icon" class="size-[1.05rem]" />
              </span>
              <span class="min-w-0">
                <span class="block text-sm font-semibold">{{ item.title }}</span>
                <span class="text-muted-foreground mt-1 block text-xs leading-6">
                  {{ item.description }}
                </span>
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </section>
</template>
