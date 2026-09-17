<script setup lang="ts">
import { DownloadIcon, MenuIcon } from '@lucide/vue'
import { Button } from '@/components/ui/button'
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from '@/components/ui/sheet'
import { NAV_ITEMS, SITE } from '@/lib/site'
import GitHubMark from './GitHubMark.vue'
import LinkButton from './LinkButton.vue'
</script>

<template>
  <Sheet>
    <SheetTrigger as-child>
      <Button variant="ghost" size="icon-sm" class="lg:hidden" aria-label="打开导航菜单">
        <MenuIcon />
      </Button>
    </SheetTrigger>
    <SheetContent side="right" class="w-72">
      <SheetHeader>
        <SheetTitle>导航</SheetTitle>
      </SheetHeader>

      <nav class="flex flex-col gap-0.5 px-4" aria-label="移动端导航">
        <a
          v-for="item in NAV_ITEMS"
          :key="item.href"
          :href="item.href"
          class="rounded-md px-3 py-2.5 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
        >
          {{ item.label }}
        </a>
      </nav>

      <div class="mt-auto flex flex-col gap-2 border-t border-border p-4">
        <LinkButton :href="SITE.repo" external variant="outline" class="w-full">
          <GitHubMark :size="16" />
          GitHub 仓库
        </LinkButton>
        <LinkButton href="#download" class="w-full">
          <DownloadIcon />
          下载 CalmBar
        </LinkButton>
      </div>
    </SheetContent>
  </Sheet>
</template>
