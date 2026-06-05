<template>
  <el-drawer
    v-model="drawer"
    title="系统配置"
    direction="rtl"
    :size="width"
    :show-close="false"
    class="prefs-drawer"
  >
    <template #header>
      <div class="flex items-center justify-between w-full px-6 py-4 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-700">
        <h2 class="text-xl font-semibold prefs-text-main prefs-font">系统配置</h2>
        <el-button
          type="primary"
          size="small"
          class="reset-btn"
          :style="{ backgroundColor: config.primaryColor, borderColor: config.primaryColor }"
          @click="resetConfig"
        >
          重置配置
        </el-button>
      </div>
    </template>

    <div class="bg-white dark:bg-gray-900 px-6">
      <div class="px-8 pt-4 pb-6">
        <div class="flex justify-center">
          <div class="inline-flex bg-gray-100 dark:bg-gray-800 rounded-xl p-1.5 border border-gray-200 dark:border-gray-700 shadow-sm">
            <div
              v-for="tab in tabs"
              :key="tab.key"
              class="px-4 py-2 text-base text-center cursor-pointer font-medium rounded-lg transition-all duration-150 ease-in-out min-w-[80px]"
              :class="[
                activeTab === tab.key
                  ? 'text-white shadow-md transform -translate-y-0.5'
                  : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-200 hover:bg-gray-50 dark:hover:bg-gray-700'
              ]"
              :style="activeTab === tab.key ? { backgroundColor: config.primaryColor } : {}"
              @click="activeTab = tab.key"
            >
              {{ tab.label }}
            </div>
          </div>
        </div>
      </div>

      <div class="pb-8 h-full overflow-y-auto">
        <div class="transition-all duration-300 ease-in-out">
          <AppearanceSettings v-if="activeTab === 'appearance'" />
          <LayoutSettings v-else-if="activeTab === 'layout'" />
          <SecuritySettings v-else-if="activeTab === 'security'" />
          <GeneralSettings v-else-if="activeTab === 'general'" />
        </div>
      </div>
    </div>
  </el-drawer>
</template>

<script setup>
  import { ref, computed, watch } from 'vue'
  import { storeToRefs } from 'pinia'
  import { ElMessage } from 'element-plus'
  import { useAppStore } from '@/pinia'
  import { setSelfSetting } from '@/api/user'
  import AppearanceSettings from './modules/appearance/index.vue'
  import LayoutSettings from './modules/layout/index.vue'
  import GeneralSettings from './modules/general/index.vue'
  import SecuritySettings from './modules/security/index.vue'

  defineOptions({
    name: 'PreferenceDrawer'
  })

  const appStore = useAppStore()
  const { config, device } = storeToRefs(appStore)

  const activeTab = ref('appearance')

  const tabs = [
    { key: 'appearance', label: '外观' },
    { key: 'layout', label: '布局' },
    { key: 'security', label: '安全' },
    { key: 'general', label: '通用' }
  ]

  const width = computed(() => {
    return device.value === 'mobile' ? '100%' : '500px'
  })

  const drawer = defineModel('drawer', {
    default: true,
    type: Boolean
  })

  const saveConfig = async () => {
    const res = await setSelfSetting(config.value)
    if (res.code === 0) {
      localStorage.setItem('originSetting', JSON.stringify(config.value))
      ElMessage.success('保存成功')
    }
  }

  const resetConfig = () => {
    appStore.resetConfig()
  }

  watch(config, async () => {
    await saveConfig();
  }, { deep: true });
</script>

<style lang="scss">
.prefs-drawer {
  .el-drawer {
    @apply bg-white dark:bg-gray-900;
  }

  .el-drawer__header {
    @apply p-0 border-0;
  }

  .el-drawer__body {
    @apply p-0;
  }
}

.prefs-font {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
}

.prefs-card-bg {
  @apply bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-4 shadow-sm;
}

.prefs-card {
  @apply bg-white dark:bg-gray-700 border border-gray-200 dark:border-gray-600 rounded-lg p-5 hover:shadow-md transition-all duration-150 ease-in-out hover:-translate-y-0.5;
}

.prefs-section-head {
  @apply flex items-center justify-center mb-6;
}

.prefs-section-title {
  @apply px-6 text-lg font-semibold text-gray-700 dark:text-gray-300;
}

.prefs-section-divider {
  @apply h-px bg-gray-200 dark:bg-gray-700 flex-1;
}

.prefs-text-main {
  @apply text-gray-900 dark:text-white;
}

.prefs-text-sub {
  @apply text-gray-600 dark:text-gray-400;
}

.prefs-section-body {
  animation: fadeInUp 0.3s ease;
}

.prefs-setting-row {
  @apply flex items-center justify-between py-4 prefs-font border-b border-gray-100 dark:border-gray-700 last:border-b-0;
}

.prefs-setting-label {
  @apply text-sm font-medium prefs-text-main;
}

.prefs-mode-toggle {
  @apply inline-flex bg-gray-100 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-1 gap-1;
}

.prefs-mode-option {
  @apply flex flex-col items-center justify-center px-3 py-2 rounded-md cursor-pointer transition-all duration-150 ease-in-out min-w-[64px];
}

.prefs-layout-card {
  @apply bg-white dark:bg-gray-700 border-2 border-gray-200 dark:border-gray-600 rounded-xl p-3 cursor-pointer transition-all duration-150 ease-in-out hover:-translate-y-1 hover:shadow-xl;
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(12px);
  }

  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* Custom scrollbar for webkit browsers */
.prefs-drawer ::-webkit-scrollbar {
  width: 6px;
}

.prefs-drawer ::-webkit-scrollbar-track {
  background: #f3f4f6;
  border-radius: 3px;
}

.prefs-drawer ::-webkit-scrollbar-thumb {
  background: #d1d5db;
  border-radius: 3px;

  &:hover {
    background: #9ca3af;
  }
}

.dark .prefs-drawer ::-webkit-scrollbar-track {
  background: #1f2937;
}

.dark .prefs-drawer ::-webkit-scrollbar-thumb {
  background: #4b5563;

  &:hover {
    background: #6b7280;
  }
}
</style>

<style lang="scss" scoped>
.reset-btn {
  @apply rounded-lg font-medium transition-all duration-150 ease-in-out hover:-translate-y-0.5 hover:brightness-90 hover:shadow-lg;
}
</style>
