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

    <div class="mb-10">
      <div class="prefs-section-head">
        <div class="prefs-section-divider"></div>
        <span class="prefs-section-title">邮件发送配置</span>
        <div class="prefs-section-divider"></div>
      </div>

      <div class="prefs-section-body">
        <div class="prefs-card-bg">
          <SettingItem label="SMTP 服务器">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">QQ：smtp.qq.com，163：smtp.163.com</span>
            </template>
            <el-input v-model="email.host" placeholder="smtp.qq.com" :disabled="emailLoading" style="max-width: 260px" />
          </SettingItem>

          <SettingItem label="端口">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">SSL 通常为 465</span>
            </template>
            <el-input-number v-model="email.port" :min="1" :max="65535" :disabled="emailLoading" />
          </SettingItem>

          <SettingItem label="发件人邮箱">
            <el-input v-model="email.from" placeholder="yourname@qq.com" :disabled="emailLoading" style="max-width: 260px" />
          </SettingItem>

          <SettingItem label="发件人昵称">
            <el-input v-model="email.nickname" placeholder="AnnaCode" :disabled="emailLoading" style="max-width: 260px" />
          </SettingItem>

          <SettingItem label="SMTP 授权码">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">{{ email.secretSet ? '已配置，留空则不修改' : 'QQ/163 邮箱设置里开启 SMTP 后获取的授权码（非登录密码）' }}</span>
            </template>
            <el-input
              v-model="email.secret"
              type="password"
              show-password
              :placeholder="email.secretSet ? '••••••（留空不修改）' : '请输入邮箱授权码'"
              :disabled="emailLoading"
              style="max-width: 260px"
              @input="email.secretChanged = true"
            />
          </SettingItem>

          <SettingItem label="使用 SSL">
            <el-switch v-model="email.isSSL" :disabled="emailLoading" />
          </SettingItem>

          <SettingItem label="LOGIN 认证">
            <template #suffix>
              <span class="text-xs text-gray-400 dark:text-gray-500 ml-2">部分企业邮箱需开启，QQ/163 一般关闭</span>
            </template>
            <el-switch v-model="email.isLoginAuth" :disabled="emailLoading" />
          </SettingItem>

          <SettingItem label="操作">
            <div class="flex items-center gap-3">
              <el-button type="primary" :loading="emailLoading" @click="saveEmailConfig">保存配置</el-button>
              <el-button :loading="emailTesting" :disabled="!email.configured" @click="handleTestEmail">发送测试邮件</el-button>
              <el-tag v-if="email.configured" type="success" size="small">已配置</el-tag>
              <el-tag v-else type="info" size="small">未配置</el-tag>
            </div>
          </SettingItem>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import {
  getCaptchaConfig,
  updateCaptchaConfig,
  getEmailConfig,
  updateEmailConfig,
  sendTestEmail
} from '@/api/security'
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

const emailLoading = ref(false)
const emailTesting = ref(false)
const email = reactive({
  host: '',
  port: 465,
  from: '',
  nickname: '',
  secret: '',
  isSSL: true,
  isLoginAuth: false,
  secretSet: false,
  secretChanged: false,
  configured: false
})

const syncEmailState = (data = {}) => {
  email.host = data.host || ''
  email.port = Number(data.port || 465)
  email.from = data.from || ''
  email.nickname = data.nickname || ''
  email.isSSL = data.isSSL ?? true
  email.isLoginAuth = data.isLoginAuth ?? false
  email.secretSet = !!data.secretSet
  email.configured = !!data.configured
  email.secret = ''
  email.secretChanged = false
}

const loadEmailConfig = async () => {
  emailLoading.value = true
  try {
    const res = await getEmailConfig()
    if (res.code !== 0) {
      return
    }
    syncEmailState(res.data)
  } finally {
    emailLoading.value = false
  }
}

const saveEmailConfig = async () => {
  emailLoading.value = true
  try {
    const res = await updateEmailConfig({
      host: email.host.trim(),
      port: Math.max(1, Number(email.port || 0)),
      from: email.from.trim(),
      nickname: email.nickname.trim(),
      secret: email.secret,
      isSSL: email.isSSL,
      isLoginAuth: email.isLoginAuth,
      secretChanged: email.secretChanged
    })
    if (res.code !== 0) {
      return
    }
    syncEmailState(res.data)
    ElMessage.success('邮件配置已保存')
  } finally {
    emailLoading.value = false
  }
}

const handleTestEmail = async () => {
  emailTesting.value = true
  try {
    const res = await sendTestEmail({ to: email.from.trim() })
    if (res.code !== 0) {
      return
    }
    ElMessage.success('测试邮件已发送，请查收')
  } finally {
    emailTesting.value = false
  }
}

onMounted(async () => {
  await loadConfig()
  await loadEmailConfig()
})
</script>
