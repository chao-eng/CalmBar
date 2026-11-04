<script setup lang="ts">
import FeatureIcon from '@/components/site/FeatureIcon.vue'
import { FEATURE_GROUPS } from '@/lib/features'
</script>

<template>
  <section id="features" class="section" aria-labelledby="features-title">
    <div class="container-page">
      <div class="reveal mx-auto max-w-2xl text-center">
        <p class="section-eyebrow">
          核心功能
        </p>
        <h2 id="features-title" class="section-title mt-2">
          十七项能力，收进一个菜单栏图标
        </h2>
        <p class="section-desc">
          六组功能，按平时用得到的地方排开。每组写清楚它管什么，边界在哪。
        </p>
      </div>

      <div class="mt-9 space-y-6">
        <div
          v-for="group in FEATURE_GROUPS"
          :key="group.id"
          class="reveal border-t border-border pt-6"
        >
          <div>
            <h3 class="text-lg font-semibold tracking-tight">
              {{ group.label }}
            </h3>
            <p class="mt-1.5 text-sm leading-relaxed text-muted-foreground">
              {{ group.summary }}
            </p>
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
  </section>
</template>
