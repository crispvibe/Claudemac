<template>
  <div
    class="relative h-full flex flex-col text-[#334155] transition-all duration-300 ease-in-out bg-transparent z-20"
    :class="isCollapse ? '' : 'px-3'"
    :style="{
      width: layoutSideWidth + 'px'
    }"
  >
    <!-- 左侧专用系统品牌舱顶 -->
    <div class="h-16 flex items-center justify-start pl-6 cursor-pointer shrink-0" @click="goHome">
      <div class="inline-flex items-center gap-2 text-[20px] font-black text-[#1e293b]">
        <el-icon color="#1F83FF" size="24"><ElementPlus /></el-icon>
        <span v-if="!isCollapse" class="tracking-wide">{{ $APP_CONFIG.appName }}</span>
      </div>
    </div>
    
    <el-scrollbar class="min-h-0 flex-1 w-full" :class="isCollapse ? '' : 'pb-4'">
      <el-menu
        :collapse="isCollapse"
        :collapse-transition="false"
        :default-active="active"
        class="!border-r-0 w-full !bg-transparent side-menu-reset"
        unique-opened
        @select="selectMenuItem"
      >
        <template v-for="item in routerStore.asyncRouters[0]?.children || []">
          <aside-component
            v-if="!item.hidden"
            :key="item.name"
            :router-info="item"
          />
        </template>
      </el-menu>
    </el-scrollbar>
    <div v-if="!isCollapse" class="mt-auto w-full shrink-0 pb-6 pt-4">
      <div
        @click="goToPerson"
        class="w-full bg-white flex items-center p-3 rounded-2xl shadow-[0_4px_24px_rgba(31,131,255,0.06)] box-border cursor-pointer hover:shadow-[0_4px_24px_rgba(31,131,255,0.12)] transition-shadow"
      >
        <div class="flex-shrink-0 w-10 h-10 rounded-full overflow-hidden bg-[#ffe8d6] flex items-center justify-center text-[#e67e22] text-sm font-bold shadow-inner">
          {{ userInitial }}
        </div>
        <div class="ml-3 flex-1 overflow-hidden flex flex-col justify-center">
          <div class="flex items-center gap-2">
            <span class="text-[14px] font-bold text-[#1e293b] truncate">{{ userStore.userInfo.nickName }}</span>
          </div>
          <span class="text-[11px] text-[#94a3b8] truncate mt-1">
            当前账号: {{ userStore.userInfo.userName }}
          </span>
        </div>
        <div class="flex-shrink-0 ml-1 p-2 flex items-center justify-center hover:bg-red-50 text-gray-400 hover:text-red-500 rounded-xl transition-colors" @click.stop="handleLogout">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-[#94a3b8]" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
          </svg>
        </div>
      </div>
    </div>
    
    <div
      class="absolute bottom-[20%] -right-[12px] w-6 h-12 bg-white flex items-center justify-center rounded-r-xl cursor-pointer shadow-[2px_4px_16px_rgba(31,131,255,0.12)] border border-gray-100 hover:scale-105 transition-transform"
      @click="toggleCollapse"
    >
      <el-icon class="text-gray-400" v-if="!isCollapse">
        <ArrowLeftBold />
      </el-icon>
      <el-icon class="text-gray-400" v-else>
        <ArrowRightBold />
      </el-icon>
    </div>
  </div>
</template>

<script setup>
  import AsideComponent from '@/view/layout/aside/asideComponent/index.vue'
  import { ref, provide, watchEffect, computed } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { useRouterStore } from '@/pinia/modules/router'
  import { useUserStore } from '@/pinia/modules/user'
  import { useAppStore } from '@/pinia'
  import { navigateByMenuName, resolveActiveMenuKey } from '@/utils/menuNavigation'
  import { storeToRefs } from 'pinia'
  import { ArrowLeftBold, ArrowRightBold, ElementPlus } from '@element-plus/icons-vue'
  import { ElMessageBox } from 'element-plus'
  
  const appStore = useAppStore()
  const { device } = storeToRefs(appStore)

  defineOptions({
    name: 'AppAsidePanel'
  })
  const route = useRoute()
  const router = useRouter()
  const routerStore = useRouterStore()
  const userStore = useUserStore()
  
  const userInitial = computed(() => (userStore.userInfo?.nickName || userStore.userInfo?.userName || '师').slice(0, 1))

  const isCollapse = ref(false)
  const active = ref('')
  const layoutSideWidth = computed(() => {
    if (!isCollapse.value) {
      return 220
    } else {
      return 60
    }
  })
  watchEffect(() => {
    active.value = resolveActiveMenuKey(route)
  })

  watchEffect(() => {
    if (device.value === 'mobile') {
      isCollapse.value = true
    } else {
      isCollapse.value = false
    }
  })

  provide('isCollapse', isCollapse)

  const selectMenuItem = (index) => {
    navigateByMenuName({
      routeName: index,
      currentRouteName: route.name,
      routeMap: routerStore.routeMap
    })
  }

  const toggleCollapse = () => {
    isCollapse.value = !isCollapse.value
  }

  // 点击极其平滑地滑入“个人主页”资料库
  const goToPerson = () => {
    router.push({ name: 'person' })
  }

  // 点击品牌舱顶回到当前角色的默认入口（带 slug，避免裸路径 404）
  const goHome = () => {
    const entryName = userStore.userInfo?.primaryRole?.defaultEntry
    if (entryName && router.hasRoute(entryName)) {
      router.push({ name: entryName })
    }
  }

  // 极度优雅带大圆角的拦截确认弹窗
  const handleLogout = () => {
    ElMessageBox.confirm('您确定要退出当前后台系统吗？', '退出确认', {
      showClose: false,
      closeOnClickModal: true,
      confirmButtonText: '安全退出',
      cancelButtonText: '暂不退出',
      type: 'warning',
      customClass: 'logout-confirm-panel'
    }).then(() => {
      userStore.LoginOut()
    }).catch(() => {})
  }
</script>

<style lang="scss" scoped>
/* 深入改变导航菜单选中底色与结构 */
::v-deep(.side-menu-reset) {
  --el-menu-bg-color: transparent !important;
  --el-menu-hover-bg-color: transparent !important;
  --el-menu-active-color: #334155 !important;
  --el-menu-text-color: #64748b !important;
  
  .el-sub-menu__title:hover,
  .el-menu-item:hover {
    color: #1f83ff !important;
    background-color: transparent !important;
    
    * {
      color: #1f83ff !important;
    }
  }
  
  /* 重点包裹选中态的高级悬浮感 */
  .el-menu-item {
    border-radius: 12px;
    margin-bottom: 4px;
    height: 48px;
    line-height: 48px;
    &.is-active {
      font-weight: 700 !important;
      background-color: #ffffff !important;
      border: none !important;
      border-radius: 12px !important;
      margin: 0 !important;
      width: 100% !important;
      box-shadow: 0 4px 16px rgba(31, 131, 255, 0.08) !important;
      color: #1F83FF !important;

      * {
        color: #1F83FF !important;
      }
    }
    
    &:not(.is-active):hover {
      background-color: rgba(0,0,0,0.03) !important;
    }
  }

  /* 去除展开内部的深色条块 */
  .el-menu--inline {
    background: transparent !important;
  }
}
</style>
