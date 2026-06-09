<template>
  <div class="flex items-center mx-4 gap-4">
    <el-popover placement="bottom-end" :width="360" trigger="click" popper-style="border-radius: 20px; border: 1px solid rgba(0,0,0,0.06); box-shadow: 0 24px 80px rgba(0,0,0,0.25), 0 8px 32px rgba(0,0,0,0.15); padding: 16px;" @show="loadNotices">
      <template #reference>
        <span class="w-8 h-8 rounded-lg flex items-center justify-center cursor-pointer text-[#86868b] hover:text-[#1f83ff] hover:bg-blue-50 transition-colors relative">
          <el-icon size="20"><Bell /></el-icon>
          <span v-if="unread > 0" class="absolute -top-[2px] -right-[2px] min-w-[16px] h-[16px] px-[4px] bg-red-500 text-white rounded-full text-[10px] leading-[16px] text-center">{{ unread > 99 ? '99+' : unread }}</span>
        </span>
      </template>
      <div class="px-2 py-1">
        <div class="flex items-center justify-between font-bold text-[#1e293b] mb-3 pb-2 border-b border-gray-100">
          <span>通知中心<span v-if="unread > 0" class="ml-2 text-[12px] font-normal text-red-500">{{ unread }} 条未读</span></span>
          <span class="text-[12px] font-normal text-[#1f83ff] cursor-pointer hover:text-blue-600" @click="handleMarkAllRead">全部已读</span>
        </div>
        <div class="flex items-center gap-2 mb-2 text-[12px]">
          <span :class="filterClass('')" @click="setCategory('')">全部</span>
          <span :class="filterClass('security')" @click="setCategory('security')">安全</span>
          <span :class="filterClass('system')" @click="setCategory('system')">系统</span>
          <span :class="filterClass('business')" @click="setCategory('business')">业务</span>
        </div>
        <div v-if="loading" class="py-8 text-center text-[12px] text-slate-400">提醒加载中...</div>
        <div v-else-if="loadError" class="py-8 text-center text-[12px] text-slate-400">提醒加载失败，请稍后重试</div>
        <div v-else-if="notices.length" class="flex flex-col gap-2 max-h-[360px] overflow-y-auto">
          <div v-for="item in notices" :key="item.id" class="flex items-start gap-3 p-2 hover:bg-slate-50 rounded-lg cursor-pointer transition-colors relative" @click="openDetail(item)">
            <div :class="['w-8 h-8 rounded-full flex items-center justify-center shrink-0', noticeBadgeClass(item.level)]">
              <el-icon><component :is="noticeIcon(item.level)" /></el-icon>
            </div>
            <div class="flex flex-col gap-1 min-w-0 flex-1">
              <span :class="['text-[13px] line-clamp-2', item.read ? 'text-slate-400' : 'text-slate-700 font-medium']">{{ item.title }}</span>
              <div class="flex items-center justify-between gap-3 text-[11px] text-slate-400">
                <span :class="noticeTagClass(item.level)">{{ categoryLabel(item.category) }}</span>
                <span class="shrink-0">{{ formatTime(item.CreatedAt) }}</span>
              </div>
            </div>
            <span v-if="!item.read" class="absolute top-3 right-3 w-[6px] h-[6px] bg-red-500 rounded-full"></span>
          </div>
        </div>
        <div v-else class="py-8 text-center text-[12px] text-slate-400">
          当前没有新的通知
        </div>
        <div class="mt-3 pt-3 border-t border-gray-100 text-center">
          <span class="text-[12px] text-gray-400 cursor-pointer hover:text-[#1f83ff] transition-colors" @click="loadNotices">刷新</span>
        </div>
      </div>
    </el-popover>

    <el-dialog v-model="detailVisible" :title="activeNotice?.title || '通知详情'" width="520px" destroy-on-close>
      <div v-if="activeNotice" class="flex flex-col gap-3 text-[13px] text-slate-700">
        <div class="flex items-center gap-2 text-[12px] text-slate-400">
          <span :class="noticeTagClass(activeNotice.level)">{{ categoryLabel(activeNotice.category) }}</span>
          <span>{{ levelLabel(activeNotice.level) }}</span>
          <span>{{ formatTime(activeNotice.CreatedAt) }}</span>
          <span v-if="activeNotice.source" class="text-slate-400">来源：{{ activeNotice.source }}</span>
        </div>
        <div class="whitespace-pre-wrap leading-6">{{ activeNotice.content || '（无详细内容）' }}</div>
        <div v-if="activeNotice.refType" class="text-[12px] text-slate-400">关联：{{ activeNotice.refType }} / {{ activeNotice.refId }}</div>
      </div>
    </el-dialog>

    <el-tooltip effect="dark" content="全屏切换" placement="bottom">
      <span class="w-8 h-8 rounded-lg flex items-center justify-center cursor-pointer text-[#86868b] hover:text-[#1f83ff] hover:bg-blue-50 transition-colors" @click="toggleFullScreen">
        <el-icon size="20"><FullScreen /></el-icon>
      </span>
    </el-tooltip>

    <el-tooltip effect="dark" content="刷新当前状态" placement="bottom">
      <span class="w-8 h-8 rounded-lg flex items-center justify-center cursor-pointer text-[#86868b] hover:text-[#1f83ff] hover:bg-blue-50 transition-colors">
      <el-icon
          :class="showRefreshAnmite ? 'animate-spin' : ''"
          @click="toggleRefresh"
          size="20"
      >
        <Refresh />
      </el-icon>
      </span>
    </el-tooltip>
  </div>
</template>

<script setup>
  import { onMounted, onBeforeUnmount, ref } from 'vue'
  import { emitter } from '@/utils/event-bus.js'
  import { Bell, Refresh, InfoFilled, WarningFilled, CircleCheckFilled, FullScreen } from '@element-plus/icons-vue'
  import {
    listNotifications,
    getUnreadCount,
    getNotificationDetail,
    markNotificationRead,
    markAllNotificationsRead
  } from '@/api/notification'

  const showRefreshAnmite = ref(false)
  const loading = ref(false)
  const loadError = ref(false)
  const notices = ref([])
  const unread = ref(0)
  const category = ref('')
  const detailVisible = ref(false)
  const activeNotice = ref(null)

  let pollingTimer = null

  const noticeIcon = (level) => {
    if (level === 'danger' || level === 'warning') return WarningFilled
    if (level === 'success') return CircleCheckFilled
    return InfoFilled
  }

  const noticeBadgeClass = (level) => {
    if (level === 'danger') return 'bg-red-100 text-red-500'
    if (level === 'warning') return 'bg-orange-100 text-orange-500'
    if (level === 'success') return 'bg-emerald-100 text-emerald-500'
    return 'bg-blue-100 text-[#1f83ff]'
  }

  const noticeTagClass = (level) => {
    if (level === 'danger') return 'text-red-500'
    if (level === 'warning') return 'text-orange-500'
    if (level === 'success') return 'text-emerald-500'
    return 'text-[#1f83ff]'
  }

  const categoryLabel = (cat) => {
    if (cat === 'security') return '安全'
    if (cat === 'business') return '业务'
    return '系统'
  }

  const levelLabel = (level) => {
    if (level === 'danger') return '严重'
    if (level === 'warning') return '警告'
    if (level === 'success') return '正常'
    return '提示'
  }

  const filterClass = (value) => {
    const active = category.value === value
    return [
      'px-2 py-[2px] rounded-full cursor-pointer transition-colors',
      active ? 'bg-[#1f83ff] text-white' : 'bg-slate-100 text-slate-500 hover:bg-slate-200'
    ].join(' ')
  }

  const setCategory = (value) => {
    if (category.value === value) return
    category.value = value
    loadNotices()
  }

  const formatTime = (raw) => {
    if (!raw) return ''
    const d = new Date(raw)
    if (Number.isNaN(d.getTime())) return ''
    const pad = (n) => String(n).padStart(2, '0')
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`
  }

  const refreshUnread = async () => {
    try {
      const res = await getUnreadCount()
      if (res.code === 0) {
        unread.value = Number(res.data?.unread || 0)
      }
    } catch (err) {
      // 静默失败，避免顶栏频繁报错
    }
  }

  const loadNotices = async () => {
    loading.value = true
    loadError.value = false
    try {
      const res = await listNotifications({
        page: 1,
        pageSize: 20,
        category: category.value
      })
      if (res.code !== 0) {
        loadError.value = true
        return
      }
      notices.value = Array.isArray(res.data?.list) ? res.data.list : []
      await refreshUnread()
    } catch (error) {
      loadError.value = true
    } finally {
      loading.value = false
    }
  }

  const openDetail = async (item) => {
    activeNotice.value = item
    detailVisible.value = true
    if (!item.read) {
      try {
        await markNotificationRead(item.id)
        item.read = true
        unread.value = Math.max(0, unread.value - 1)
      } catch (err) {
        // 忽略失败
      }
    }
    try {
      const res = await getNotificationDetail(item.id)
      if (res.code === 0 && res.data) {
        activeNotice.value = { ...item, ...res.data, read: true }
      }
    } catch (err) {
      // 详情拉取失败则沿用列表数据
    }
  }

  const handleMarkAllRead = async () => {
    try {
      const res = await markAllNotificationsRead()
      if (res.code === 0) {
        notices.value = notices.value.map((item) => ({ ...item, read: true }))
        unread.value = 0
      }
    } catch (err) {
      // 静默
    }
  }

  const toggleRefresh = () => {
    showRefreshAnmite.value = true
    emitter.emit('reload')
    refreshUnread()
    setTimeout(() => {
      showRefreshAnmite.value = false
    }, 1000)
  }

  const toggleFullScreen = () => {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen?.()
    } else {
      document.exitFullscreen?.()
    }
  }

  onMounted(async () => {
    await refreshUnread()
    // 每 60 秒静默刷新一次未读数
    pollingTimer = window.setInterval(() => {
      refreshUnread()
    }, 60000)
  })

  onBeforeUnmount(() => {
    if (pollingTimer) {
      window.clearInterval(pollingTimer)
      pollingTimer = null
    }
  })
</script>

<style scoped lang="scss"></style>
