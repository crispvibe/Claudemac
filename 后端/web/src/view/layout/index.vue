<template>
  <div
    class="w-screen h-screen p-2 lg:p-3 box-border bg-gradient-to-br from-[#e0f2fe] via-[#f1f5f9] to-[#dbeafe] dark:from-[#0f172a] dark:via-[#1e293b] dark:to-[#020617] text-[#1d1d1f] transition-colors duration-300 overflow-hidden"
  >
    <el-watermark
      v-if="config.show_watermark"
      :font="font"
      :z-index="9999"
      :gap="[180, 150]"
      class="!absolute !inset-0 !pointer-events-none"
      :content="userStore.userInfo.nickName"
    />

    <section class="relative flex h-full w-full overflow-hidden rounded-[28px] border border-white/40 bg-white/35 shadow-[0_16px_56px_rgba(15,23,42,0.08)] backdrop-blur-[36px] dark:border-white/5 dark:bg-slate-900/35 dark:shadow-none">
      <aside
        v-if="showPrimaryRail"
        class="shrink-0 z-30 bg-transparent"
      >
        <app-nav />
      </aside>

      <aside
        v-if="showSecondaryRail"
        class="shrink-0 z-20 bg-transparent"
      >
        <app-nav mode="normal" />
      </aside>

      <main class="flex min-w-0 flex-1">
        <div class="relative flex h-full w-full flex-col overflow-hidden rounded-l-[30px] border-l border-white/70 bg-[#f6f8fb] shadow-[-14px_0_52px_rgba(15,23,42,0.06)] dark:border-white/5 dark:bg-[#0b1220]">
          <app-topbar class="z-20 shrink-0" />

          <section class="flex-1 overflow-auto px-4 py-3">
            <router-view v-if="reloadFlag" v-slot="{ Component, route }">
              <section
                id="scene-loader-anchor"
                class="scene-shell w-full overflow-hidden rounded-3xl bg-transparent"
              >
                <transition
                  mode="out-in"
                  :name="route.meta.transitionType || config.transition_type"
                >
                  <keep-alive :include="routerStore.keepAliveRouters">
                    <component :is="Component" :key="route.fullPath" />
                  </keep-alive>
                </transition>
              </section>
            </router-view>
            <BottomInfo />
          </section>
        </div>
      </main>
    </section>
  </div>
</template>

<script setup>
  import AppNav from '@/view/layout/aside/index.vue'
  import AppTopbar from '@/view/layout/header/index.vue'
  import useResponsive from '@/hooks/responsive'
  import BottomInfo from '@/components/bottomInfo/bottomInfo.vue'
  import { emitter } from '@/utils/event-bus.js'
  import { computed, ref, onMounted, nextTick, reactive, watchEffect } from 'vue'
  import { useRouter, useRoute } from 'vue-router'
  import { useRouterStore } from '@/pinia/modules/router'
  import { useUserStore } from '@/pinia/modules/user'
  import { useAppStore } from '@/pinia'
  import { storeToRefs } from 'pinia'
  import '@/style/transition.scss'
  const appStore = useAppStore()
  const { config, isDark, device } = storeToRefs(appStore)

  defineOptions({
    name: 'ControlShell'
  })

  useResponsive(true)
  const font = reactive({
    color: 'rgba(0, 0, 0, .15)'
  })

  watchEffect(() => {
    font.color = isDark.value ? 'rgba(255,255,255, .15)' : 'rgba(0, 0, 0, .15)'
  })

  const router = useRouter()
  const route = useRoute()
  const routerStore = useRouterStore()

  const showPrimaryRail = computed(() => {
    return (
      config.value.side_mode === 'normal' ||
      config.value.side_mode === 'sidebar' ||
      (device.value === 'mobile' && config.value.side_mode === 'head') ||
      (device.value === 'mobile' && config.value.side_mode === 'combination')
    )
  })

  const showSecondaryRail = computed(() => {
    return config.value.side_mode === 'combination' && device.value !== 'mobile'
  })

  onMounted(() => {
    // 挂载一些通用的事件
    emitter.on('reload', reload)
    if (userStore.loadingInstance) {
      userStore.loadingInstance.close()
    }
  })

  const userStore = useUserStore()

  const reloadFlag = ref(true)
  let reloadTimer = null
  const reload = async () => {
    if (reloadTimer) {
      window.clearTimeout(reloadTimer)
    }
    reloadTimer = window.setTimeout(async () => {
      if (route.meta.keepAlive) {
        reloadFlag.value = false
        await nextTick()
        reloadFlag.value = true
      } else {
        const title = route.meta.title
        router.push({ name: 'Reload', params: { title } })
      }
    }, 400)
  }
</script>

<style lang="scss"></style>
