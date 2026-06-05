<template>
  <div class="captcha-settings-page">
    <div class="surface-panel">
      <div class="page-header">
        <div class="page-title">登录验证码</div>
        <div class="page-subtitle">
          当前使用滑块人机验证（拖动滑块填充缺口），可实时生效，无需重启。
          配置项控制<strong>何时</strong>触发验证码：每次登录必填、或连续失败后触发。
        </div>
      </div>

      <el-form label-width="140px" label-position="left" :disabled="loading">
        <el-form-item label="启用验证码">
          <el-switch v-model="captchaEnabled" :loading="loading" @change="handleCaptchaSwitch" />
          <span class="field-hint">关闭后任何登录请求都不要求验证码（仅建议内网环境使用）。</span>
        </el-form-item>

        <el-form-item label="触发策略">
          <el-radio-group
            v-model="mode"
            :disabled="!captchaEnabled || loading"
            @change="handleModeChange"
          >
            <el-radio-button label="always">每次登录必填</el-radio-button>
            <el-radio-button label="threshold">连续失败后触发</el-radio-button>
          </el-radio-group>
          <div class="field-hint">
            <span v-if="mode === 'always'">每次调用 /auth/login 均返回新的验证码挑战。</span>
            <span v-else>仅当同一账号/IP 连续登录失败次数达到阈值后才开启验证码。</span>
          </div>
        </el-form-item>

        <el-form-item label="失败阈值">
          <el-input-number
            v-model="threshold"
            :min="1"
            :max="20"
            :disabled="!captchaEnabled || mode !== 'threshold' || loading"
            @change="saveConfig"
          />
          <span class="field-hint">仅在「连续失败后触发」模式下生效，推荐 3-5 次。</span>
        </el-form-item>

        <el-form-item label="统计窗口">
          <el-input-number
            v-model="openCaptchaTimeOut"
            :min="0"
            :max="86400"
            :step="60"
            :disabled="loading"
            @change="saveConfig"
          />
          <span class="field-hint">登录失败计数保留时长，单位秒；0 表示永不过期（推荐 900 = 15 分钟）。</span>
        </el-form-item>

        <el-form-item label="当前状态">
          <div class="status-panel">
            <el-tag :type="statusTag.type" size="small">{{ statusTag.text }}</el-tag>
            <span class="status-desc">{{ statusDescription }}</span>
          </div>
        </el-form-item>
      </el-form>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { getCaptchaConfig, updateCaptchaConfig } from '@/api/security'

defineOptions({
  name: 'SecurityCaptchaPage'
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

const statusTag = computed(() => {
  if (!captchaEnabled.value) {
    return { type: 'danger', text: '已禁用' }
  }
  if (mode.value === 'always') {
    return { type: 'success', text: '每次登录强制' }
  }
  return { type: 'warning', text: `失败 ${threshold.value} 次后启用` }
})

const statusDescription = computed(() => {
  if (!captchaEnabled.value) {
    return '验证码功能已关闭，存在被暴力破解风险，建议尽快启用。'
  }
  if (mode.value === 'always') {
    return '防护等级：高。每次登录请求都会强制验证码校验。'
  }
  return `防护等级：中。统计窗口 ${openCaptchaTimeOut.value} 秒，失败达到 ${threshold.value} 次后开启。`
})

const loadConfig = async () => {
  loading.value = true
  try {
    const res = await getCaptchaConfig()
    if (res.code !== 0) return
    syncState(res.data)
  } finally {
    loading.value = false
  }
}

const saveConfig = async () => {
  loading.value = true
  try {
    const res = await updateCaptchaConfig(buildPayload())
    if (res.code !== 0) return
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

<style scoped>
.captcha-settings-page {
  padding: 20px;
}

.surface-panel {
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color-lighter);
  border-radius: 12px;
  padding: 28px 32px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.03);
}

.page-header {
  margin-bottom: 28px;
  padding-bottom: 20px;
  border-bottom: 1px solid var(--el-border-color-lighter);
}

.page-title {
  font-size: 20px;
  font-weight: 600;
  color: var(--el-text-color-primary);
}

.page-subtitle {
  margin-top: 6px;
  font-size: 13px;
  color: var(--el-text-color-secondary);
}

.field-hint {
  display: inline-block;
  margin-left: 12px;
  font-size: 12px;
  color: var(--el-text-color-secondary);
  line-height: 1.6;
}

.field-hint + .field-hint,
.field-hint.block {
  display: block;
  margin-left: 0;
  margin-top: 4px;
}

.status-panel {
  display: flex;
  align-items: center;
  gap: 12px;
}

.status-desc {
  font-size: 13px;
  color: var(--el-text-color-regular);
}
</style>
