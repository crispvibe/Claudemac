<template>
  <div
    class="flex justify-between sticky top-0 w-full z-10 h-16 bg-transparent transition-all duration-300"
  >
    <!-- Header 现完全居于右主舱段顶部，不再涉足左屏。左侧留空即可 -->
    <div class="flex items-center h-full flex-1 w-0 overflow-hidden">
      <route-tabs v-if="config.showTabs" class="w-full shrink-0" />
    </div>

    <!-- 右侧工具区 -->    
    <div class="flex px-6 items-center">
      <tools />
    </div>
  </div>
</template>

<script setup>
  import { useAppStore } from '@/pinia'
  import { storeToRefs } from 'pinia'
  import Tools from '@/view/layout/header/tools.vue'
  import RouteTabs from '@/view/layout/tabs/index.vue'

  const appStore = useAppStore()
  const { config } = storeToRefs(appStore)
</script>

<style scoped lang="scss"></style>
