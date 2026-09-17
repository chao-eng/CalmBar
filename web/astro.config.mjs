// @ts-check
import { defineConfig } from 'astro/config'
import mdx from '@astrojs/mdx'
import sitemap from '@astrojs/sitemap'
import vue from '@astrojs/vue'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  site: 'https://calmbar.bujic.cc',
  trailingSlash: 'ignore',
  integrations: [vue(), mdx(), sitemap()],
  vite: {
    plugins: [tailwindcss()],
  },
})
