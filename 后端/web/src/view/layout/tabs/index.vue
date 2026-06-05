<template>
  <section class="tab-strip-shell">
    <div class="tab-strip-track">
      <el-tabs
        v-model="activeValue"
        :closable="!(historys.length === 1 && $route.name === defaultEntry)"
        type="card"
        class="tab-strip-tabs"
        @contextmenu.prevent="openContextMenu($event)"
        @tab-click="changeTab"
        @tab-remove="removeTab"
        @click.middle.prevent="middleCloseTab($event)"
      >
        <el-tab-pane
          v-for="item in historys"
          :key="getFmtString(item)"
          :label="item.meta.title"
          :name="getFmtString(item)"
          :tab="item"
          class="border-none"
        >
          <template #label>
            <span
              :tab="item"
              class="tab-chip"
              :class="resolveTabChipClass(item)"
            >
              <span
                class="tab-chip__mark"
                :class="resolveTabMarkClass(item)"
              />
              <span class="tab-chip__text">{{ fmtTitle(item.meta.title, item) }}</span>
            </span>
          </template>
        </el-tab-pane>
      </el-tabs>
    </div>

    <!--自定义右键菜单html代码-->
    <menu
      v-show="contextMenuVisible"
      :style="{ left: left + 'px', top: top + 'px' }"
      class="tab-action-menu"
    >
      <li @click="closeAll">关闭所有</li>
      <li @click="closeLeft">关闭左侧</li>
      <li @click="closeRight">关闭右侧</li>
      <li @click="closeOther">关闭其他</li>
    </menu>
  </section>
</template>

<script setup>
  import { emitter } from '@/utils/event-bus.js'
  import { computed, onUnmounted, ref, watch, nextTick } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useUserStore } from '@/pinia/modules/user'
  import { fmtTitle } from '@/utils/route-title'

  defineOptions({
    name: 'RouteHistoryBar'
  })

  const route = useRoute()
  const router = useRouter()

  const getFmtString = (item) => {
    return item.name + JSON.stringify(item.query) + JSON.stringify(item.params)
  }

  const historys = ref([])
  const activeValue = ref('')
  const contextMenuVisible = ref(false)

  const userStore = useUserStore()

  const left = ref(0)
  const top = ref(0)
  const isCollapse = ref(false)
  const isMobile = ref(false)
  const rightActive = ref('')
  const bodyClickHandler = () => {
    contextMenuVisible.value = false
  }
  const defaultEntry = computed(
    () => userStore.userInfo.primaryRole.defaultEntry
  )
  const resolveTriggerTabId = (event) => {
    const target = event?.target
    if (!(target instanceof HTMLElement)) {
      return ''
    }
    return target.closest('[id^="tab-"]')?.id?.substring(4) || ''
  }
  const resolveTabChipClass = (item) => {
    return activeValue.value === getFmtString(item)
      ? 'tab-chip--active'
      : 'tab-chip--idle'
  }
  const resolveTabMarkClass = (item) => {
    return activeValue.value === getFmtString(item)
      ? 'tab-chip__mark--active'
      : 'tab-chip__mark--idle'
  }
  const openContextMenu = (e) => {
    if (historys.value.length === 1 && route.name === defaultEntry.value) {
      return false
    }
    const id = resolveTriggerTabId(e)
    if (id) {
      contextMenuVisible.value = true

      left.value = e.clientX
      top.value = e.clientY + 10
      rightActive.value = id
    }
  }
  const closeAll = () => {
    historys.value = [
      {
        name: defaultEntry.value,
        meta: {
          title: '首页'
        },
        params: {}
      }
    ]
    router.push({ name: defaultEntry.value })
    contextMenuVisible.value = false
    sessionStorage.setItem('historys', JSON.stringify(historys.value))
  }
  const closeLeft = () => {
    let right
    const rightIndex = historys.value.findIndex((item) => {
      if (getFmtString(item) === rightActive.value) {
        right = item
      }
      return getFmtString(item) === rightActive.value
    })
    const activeIndex = historys.value.findIndex(
      (item) => getFmtString(item) === activeValue.value
    )
    historys.value.splice(0, rightIndex)
    if (rightIndex > activeIndex) {
      router.push(right)
    }
    sessionStorage.setItem('historys', JSON.stringify(historys.value))
  }
  const closeRight = () => {
    let right
    const leftIndex = historys.value.findIndex((item) => {
      if (getFmtString(item) === rightActive.value) {
        right = item
      }
      return getFmtString(item) === rightActive.value
    })
    const activeIndex = historys.value.findIndex(
      (item) => getFmtString(item) === activeValue.value
    )
    historys.value.splice(leftIndex + 1, historys.value.length)
    if (leftIndex < activeIndex) {
      router.push(right)
    }
    sessionStorage.setItem('historys', JSON.stringify(historys.value))
  }
  const closeOther = () => {
    let right
    historys.value = historys.value.filter((item) => {
      if (getFmtString(item) === rightActive.value) {
        right = item
      }
      return getFmtString(item) === rightActive.value
    })
    router.push(right)
    sessionStorage.setItem('historys', JSON.stringify(historys.value))
  }
  const isSame = (route1, route2) => {
    if (route1.name !== route2.name) {
      return false
    }
    if (
      Object.keys(route1.query).length !== Object.keys(route2.query).length ||
      Object.keys(route1.params).length !== Object.keys(route2.params).length
    ) {
      return false
    }
    for (const key in route1.query) {
      if (route1.query[key] !== route2.query[key]) {
        return false
      }
    }
    for (const key in route1.params) {
      if (route1.params[key] !== route2.params[key]) {
        return false
      }
    }
    return true
  }
  const setTab = (route) => {
    if (!historys.value.some((item) => isSame(item, route))) {
      const obj = {}
      obj.name = route.name
      obj.meta = { ...route.meta }
      delete obj.meta.matched
      obj.query = route.query
      obj.params = route.params
      historys.value.push(obj)
    }
    window.sessionStorage.setItem('activeValue', getFmtString(route))
  }

  const historyMap = ref({})

  const changeTab = (TabsPaneContext) => {
    const name = TabsPaneContext?.props?.name
    if (!name) return
    const tab = historyMap.value[name]
    router.push({
      name: tab.name,
      query: tab.query,
      params: tab.params
    })
  }
  const removeTab = (tab) => {
    const index = historys.value.findIndex((item) => getFmtString(item) === tab)
    if (getFmtString(route) === tab) {
      if (historys.value.length === 1) {
        router.push({ name: defaultEntry.value })
      } else {
        if (index < historys.value.length - 1) {
          router.push({
            name: historys.value[index + 1].name,
            query: historys.value[index + 1].query,
            params: historys.value[index + 1].params
          })
        } else {
          router.push({
            name: historys.value[index - 1].name,
            query: historys.value[index - 1].query,
            params: historys.value[index - 1].params
          })
        }
      }
    }
    historys.value.splice(index, 1)
  }

  watch(
    () => contextMenuVisible.value,
    () => {
      if (contextMenuVisible.value) {
        document.body.addEventListener('click', bodyClickHandler)
      } else {
        document.body.removeEventListener('click', bodyClickHandler)
      }
    }
  )

  watch(
    () => route,
    (to) => {
      if (to.name === 'Login' || to.name === 'Reload') {
        return
      }
      historys.value = historys.value.filter((item) => !item.meta.closeTab)
      setTab(to)
      sessionStorage.setItem('historys', JSON.stringify(historys.value))
      activeValue.value = window.sessionStorage.getItem('activeValue')
    },
    { deep: true }
  )

  watch(
    () => historys.value,
    () => {
      sessionStorage.setItem('historys', JSON.stringify(historys.value))
      historyMap.value = {}
      historys.value.forEach((item) => {
        historyMap.value[getFmtString(item)] = item
      })
      emitter.emit('setKeepAlive', historys.value)
    },
    {
      deep: true
    }
  )

  const initPage = () => {
    // 全局监听 关闭当前页面函数
    emitter.on('closeThisPage', () => {
      removeTab(getFmtString(route))
    })
    // 全局监听 关闭所有页面函数
    emitter.on('closeAllPage', () => {
      closeAll()
    })
    emitter.on('mobile', (data) => {
      isMobile.value = data
    })
    emitter.on('collapse', (data) => {
      isCollapse.value = data
    })

    emitter.on('setQuery', (data) => {
      const index = historys.value.findIndex(
        (item) => getFmtString(item) === activeValue.value
      )
      historys.value[index].query = data
      activeValue.value = getFmtString(historys.value[index])
      const currentUrl = window.location.href.split('?')[0]
      const currentSearchParams = new URLSearchParams(data).toString()
      window.history.replaceState(
        {},
        '',
        `${currentUrl}?${currentSearchParams}`
      )
      sessionStorage.setItem('historys', JSON.stringify(historys.value))
    })

    emitter.on('switchTab', async (data) => {
      const index = historys.value.findIndex((item) => item.name === data.name)
      if (index < 0) {
        return
      }
      for (const key in data.query) {
        data.query[key] = String(data.query[key])
      }
      for (const key in data.params) {
        data.params[key] = String(data.params[key])
      }

      historys.value[index].query = data.query || {}
      historys.value[index].params = data.params || {}
      await nextTick()
      router.push(historys.value[index])
    })
    const initHistorys = [
      {
        name: defaultEntry.value,
        meta: {
          title: '首页'
        },
        query: {},
        params: {}
      }
    ]
    setTab(route)
    historys.value =
      JSON.parse(sessionStorage.getItem('historys')) || initHistorys
    if (!window.sessionStorage.getItem('activeValue')) {
      activeValue.value = getFmtString(route)
    } else {
      activeValue.value = window.sessionStorage.getItem('activeValue')
    }
    if (window.sessionStorage.getItem('needCloseAll') === 'true') {
      closeAll()
      window.sessionStorage.removeItem('needCloseAll')
    }
  }
  initPage()

  onUnmounted(() => {
    emitter.off('collapse')
    emitter.off('mobile')
    document.body.removeEventListener('click', bodyClickHandler)
  })

  const middleCloseTab = (e) => {
    if (historys.value.length === 1 && route.name === defaultEntry.value) {
      return false
    }
    const id = resolveTriggerTabId(e)
    if (id) {
      removeTab(id)
    }
  }
</script>

<style lang="scss" scoped>
  .tab-strip-shell {
    @apply relative;

    .tab-strip-track {
      @apply w-full;
    }

    .tab-strip-tabs {
      @apply w-full pt-2 pl-4;
    }

    .tab-chip {
      @apply inline-flex items-center gap-2;
    }

    .tab-chip__text {
      @apply leading-none;
    }

    .tab-chip__mark {
      @apply inline-block rounded-full;
      width: 6px;
      height: 6px;
    }

    .tab-chip--active {
      color: #1d1d1f;
    }

    .tab-chip--idle {
      @apply text-gray-600 dark:text-slate-400;
    }

    .tab-chip__mark--active {
      background-color: #1d1d1f;
    }

    .tab-chip__mark--idle {
      background-color: rgba(100, 116, 139, 0.45);
    }
  }

  .tab-action-menu {
    @apply fixed bg-white dark:bg-slate-700 z-[1000] rounded shadow border border-slate-200 dark:border-slate-600 py-1 min-w-[120px];
  }

  .tab-action-menu li {
    @apply text-slate-700 dark:text-slate-200 text-base list-none px-4 py-1.5 hover:bg-gray-100 dark:hover:bg-gray-600 cursor-pointer;
  }

  $base-tag-item-height: 4rem;

  .tab-strip-shell {
    ::v-deep(.el-tabs--card > .el-tabs__header) {
      border: none !important;
      margin-bottom: 0 !important;
    }
    ::v-deep(.el-tabs__nav-scroll) {
      padding: 0 4px;
    }
    ::v-deep(.el-tabs__nav) {
      border: none !important;
    }
    ::v-deep(.el-tabs__header) {
      border-bottom: none !important;
    }
    
    ::v-deep(.el-tabs__item) {
      box-sizing: border-box;
      border: none !important;
      background: transparent;
      border-radius: 100px !important;
      margin-right: 8px;
      margin-left: 0;
      &:hover {
        background-color: rgba(0,0,0,0.04);
        color: #1d1d1f;
      }

      &.is-active {
        background-color: #ffffff !important;
        color: #1d1d1f !important;
        box-shadow: 0 2px 8px -2px rgba(0,0,0,0.08) !important;
      }
    }
  }
</style>
