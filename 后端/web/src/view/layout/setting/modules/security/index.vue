<template>
  <div class="prefs-font">
    <div class="mb-10">
      <div class="prefs-section-head">
        <div class="prefs-section-divider"></div>
        <span class="prefs-section-title">登录安全</span>
        <div class="prefs-section-divider"></div>
      </div>

      <div class="prefs-section-body">
        <div class="prefs-card-bg">
          <SettingItem label="启用验证码">
            <el-switch v-model="captchaEnabled" :loading="loading" @change="handleCaptchaSwitch" />
          </SettingItem>

          <SettingItem label="触发策略">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">0 表示每次登录都验证</span>
            </template>
            <div class="flex items-center gap-3">
              <el-radio-group v-model="mode" :disabled="!captchaEnabled || loading" @change="handleModeChange">
                <el-radio-button label="always">每次登录</el-radio-button>
                <el-radio-button label="threshold">失败后触发</el-radio-button>
              </el-radio-group>
            </div>
          </SettingItem>

          <SettingItem label="失败阈值">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">连续失败达到阈值后开启验证码</span>
            </template>
            <el-input-number
              v-model="threshold"
              :min="1"
              :max="20"
              :disabled="!captchaEnabled || mode !== 'threshold' || loading"
              @change="saveConfig"
            />
          </SettingItem>

          <SettingItem label="统计窗口">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">登录失败计数保留时长（秒）</span>
            </template>
            <el-input-number
              v-model="openCaptchaTimeOut"
              :min="0"
              :max="86400"
              :disabled="loading"
              @change="saveConfig"
            />
          </SettingItem>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { getCaptchaConfig, updateCaptchaConfig } from '@/api/security'
import SettingItem from '../../components/settingItem.vue'

defineOptions({
  name: 'SecuritySettings'
})

const loading = ref(false)
const captchaEnabled = ref(false)
const mode = ref('always')
const threshold = ref(3)
const openCaptchaTimeOut = ref(900)

const syncState = (data = {}) => {
  const openCaptcha = Number(data.openCaptcha ?? -1)
  captchaEnabled.value = openCaptcha >= 0
  mode.value = openCaptcha === 0 ? 'always' : 'threshold'
  threshold.value = openCaptcha > 0 ? openCaptcha : 3
  openCaptchaTimeOut.value = Number(data.openCaptchaTimeOut ?? 900)
}

const buildPayload = () => {
  let openCaptcha = -1
  if (captchaEnabled.value) {
    openCaptcha = mode.value === 'always' ? 0 : Math.max(1, Number(threshold.value || 1))
  }
  return {
    openCaptcha,
    openCaptchaTimeOut: Math.max(0, Number(openCaptchaTimeOut.value || 0))
  }
}

const loadConfig = async () => {
  loading.value = true
  try {
    const res = await getCaptchaConfig()
    if (res.code !== 0) {
      return
    }
    syncState(res.data)
  } finally {
    loading.value = false
  }
}

const saveConfig = async () => {
  loading.value = true
  try {
    const res = await updateCaptchaConfig(buildPayload())
    if (res.code !== 0) {
      return
    }
    syncState(res.data)
    ElMessage.success('验证码配置已保存')
  } finally {
    loading.value = false
  }
}

const handleCaptchaSwitch = async () => {
  await saveConfig()
}

const handleModeChange = async () => {
  await saveConfig()
}

onMounted(async () => {
  await loadConfig()
})
</script>
