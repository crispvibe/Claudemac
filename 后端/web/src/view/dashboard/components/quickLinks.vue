<template>
  <div class="mt-4 w-full">
    <div class="text-xs tracking-wide text-black/60 dark:text-white/60">快捷入口</div>
    <div class="mt-3 grid grid-cols-3 gap-3 sm:grid-cols-4">
      <div
        v-for="(item, index) in shortcuts"
        :key="index"
        class="flex flex-col items-center group cursor-pointer"
        @click="toPath(item)"
      >
        <div
          class="w-10 h-10 rounded-lg border border-black/10 dark:border-white/10 flex items-center justify-center text-black/70 dark:text-white/70 group-hover:bg-[var(--el-color-primary)] group-hover:text-white transition-colors"
        >
          <el-icon><component :is="resolveIcon(item.routeName)" /></el-icon>
        </div>
        <div class="mt-2 text-[11px] text-black/70 dark:text-white/70">
          {{ item.title }}
        </div>
      </div>
    </div>

    <div class="mt-6 text-xs tracking-wide text-black/60 dark:text-white/60">最近访问</div>
    <div class="mt-3 grid grid-cols-3 gap-3 sm:grid-cols-4">
      <div
        v-for="(item, index) in recentVisits"
        :key="index"
        class="flex flex-col items-center group cursor-pointer"
        @click="openLink(item)"
      >
        <div
          class="w-10 h-10 rounded-lg border border-black/10 dark:border-white/10 flex items-center justify-center text-black/70 dark:text-white/70 group-hover:bg-[var(--el-color-primary)] group-hover:text-white transition-colors"
        >
          <el-icon><component :is="resolveIcon(item.routeName)" /></el-icon>
        </div>
        <div class="mt-2 text-[11px] text-black/70 dark:text-white/70">
          {{ item.title }}
        </div>
      </div>
    </div>
  </div>
</template>
<script setup>
  import {
    Menu,
    Link,
    User,
    Service,
    Histogram,
    Tickets
  } from '@element-plus/icons-vue'
  import { onMounted, ref } from 'vue'
  import { useRouter } from 'vue-router'
  const router = useRouter()

  const props = defineProps({
    shortcuts: {
      type: Array,
      default: () => []
    }
  })

  const recentVisits = ref([])
  const iconMap = {
    navigation: Menu,
    apiCatalog: Link,
    roles: Service,
    accounts: User,
    operationLogs: Histogram,
    dashboard: Tickets,
    home: Tickets
  }

  const isLocalPath = (value) => typeof value === 'string' && value.startsWith('/') && !value.startsWith('//')

  const resolveIcon = (routeName) => {
    return iconMap[routeName] || Tickets
  }

  const toPath = (item) => {
    if (!item?.routeName) {
      return
    }
    router.push({ name: item.routeName })
  }

  const openLink = (item) => {
    if (item?.routeName) {
      router.push({ name: item.routeName, query: item.query || {}, params: item.params || {} })
      return
    }
    if (isLocalPath(item.path)) {
      window.open(item.path, '_blank')
    }
  }

  const syncRecentVisits = () => {
    const historys = JSON.parse(sessionStorage.getItem('historys') || '[]')
    const dedup = new Map()
    historys
      .filter((item) => item?.name && !['Login', 'Reload'].includes(item.name))
      .reverse()
      .forEach((item) => {
        if (!dedup.has(item.name)) {
          dedup.set(item.name, {
            title: item.meta?.title || item.name,
            routeName: item.name,
            query: item.query || {},
            params: item.params || {}
          })
        }
      })
    recentVisits.value = Array.from(dedup.values()).slice(0, 4)
  }

  onMounted(() => {
    syncRecentVisits()
  })
</script>

<style scoped lang="scss"></style>
