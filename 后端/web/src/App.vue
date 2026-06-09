<template>
  <div
    id="app"
    class="bg-gray-50 text-slate-700 !dark:text-slate-500 dark:bg-slate-800"
  >
    <el-config-provider :locale="zhCn" :size="appStore.config.global_size">
      <router-view />
      <Application />
    </el-config-provider>
  </div>
</template>

<script setup>
  import zhCn from 'element-plus/dist/locale/zh-cn.mjs'
  import Application from '@/components/application/index.vue'
  import { useAppStore } from '@/pinia'

  const appStore = useAppStore()
  defineOptions({
    name: 'App'
  })
</script>
<style lang="scss">
  // 引入初始化样式
  #app {
    height: 100vh;
    overflow: hidden;
    font-weight: 400 !important;
  }

  .el-button {
    font-weight: 400 !important;
  }

  .scene-shell {
    min-height: calc(100% - 3rem);
  }

  .panel-frame {
    height: calc(100% - 2.5rem);
  }

  .panel-frame-wide {
    height: calc(100% - 4.5rem);
  }
</style>
