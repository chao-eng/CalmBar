<script setup lang="ts">
import {
  AudioLinesIcon,
  BatteryChargingIcon,
  ClipboardListIcon,
  CoffeeIcon,
  CommandIcon,
  LanguagesIcon,
  LockIcon,
  MouseIcon,
  MusicIcon,
  PanelTopIcon,
  RocketIcon,
  ScanTextIcon,
  SettingsIcon,
  ShieldCheckIcon,
  ThermometerIcon,
  Trash2Icon,
  VideoIcon,
} from '@lucide/vue'
import type { Component } from 'vue'
import type { FeatureIconKey } from '@/lib/features'

const props = defineProps<{
  name: FeatureIconKey
  class?: string
}>()

const ICONS: Record<FeatureIconKey, Component> = {
  thermometer: ThermometerIcon,
  battery: BatteryChargingIcon,
  command: CommandIcon,
  menu: PanelTopIcon,
  mouse: MouseIcon,
  clipboard: ClipboardListIcon,
  coffee: CoffeeIcon,
  music: MusicIcon,
  scan: ScanTextIcon,
  languages: LanguagesIcon,
  audio: AudioLinesIcon,
  video: VideoIcon,
  trash: Trash2Icon,
  shield: ShieldCheckIcon,
  lock: LockIcon,
  settings: SettingsIcon,
  rocket: RocketIcon,
}
</script>

<template>
  <component :is="ICONS[props.name]" :class="props.class" />
</template>
