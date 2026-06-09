<template>
  <div class="h-screen w-screen bg-[#e8ecf1] relative flex items-center justify-center overflow-hidden">
    <!-- Main Glass Container -->
    <div class="w-full max-w-[1200px] h-[720px] bg-white/70 backdrop-blur-2xl rounded-[24px] shadow-[0_32px_64px_-16px_rgba(0,0,0,0.08)] border border-white/60 relative flex overflow-hidden">
      
      <!-- Left Form Section -->
      <div class="w-full md:w-[480px] shrink-0 h-full p-12 pr-16 flex flex-col justify-center relative z-10 bg-white">
        <!-- Logo -->
        <div class="absolute top-8 left-12 flex items-center gap-2 font-bold text-xl text-gray-800 tracking-tight">
          <div class="w-8 h-8 bg-[#0052d9] rounded flex items-center justify-center text-white text-lg">
            H
          </div>
          Heyu Tech.
        </div>

        <!-- Title Area -->
        <div class="mt-8 mb-10">
          <h1 class="text-[36px] font-bold text-[#1a1a1a] leading-tight tracking-tight">登录到</h1>
          <h1 class="text-[36px] font-bold text-[#1a1a1a] leading-tight tracking-tight mb-2">系统管理后台</h1>
        </div>

        <el-form
          ref="loginForm"
          :model="loginFormData"
          :rules="rules"
          :validate-on-rule-change="false"
          @submit.prevent="submitForm"
          @keydown.enter.prevent="submitForm"
          class="space-y-6"
        >
          <el-form-item prop="username" class="!mb-6">
            <el-input
              v-model="loginFormData.username"
              placeholder="请输入账号"
              class="h-[48px] login-input"
              clearable
              autofocus
              autocomplete="username"
              spellcheck="false"
            >
              <template #prefix>
                <el-icon class="text-gray-400 text-lg"><User /></el-icon>
              </template>
            </el-input>
          </el-form-item>
          
          <el-form-item prop="password" class="!mb-4">
            <el-input
              v-model="loginFormData.password"
              show-password
              type="password"
              placeholder="请输入密码"
              class="h-[48px] login-input"
              autocomplete="current-password"
            >
              <template #prefix>
                <el-icon class="text-gray-400 text-lg"><Lock /></el-icon>
              </template>
            </el-input>
          </el-form-item>

          <!-- Remember me & Forgot password -->
          <div class="flex items-center justify-between !mb-8 px-1">
            <el-checkbox v-model="rememberMe" class="!text-sm text-gray-500 !font-normal">自动登录</el-checkbox>
            <a href="javascript:void(0)" class="text-sm text-gray-400 hover:text-[#0052d9] transition-colors">忘记密码?</a>
          </div>

          <el-form-item class="!mb-0">
            <el-button
              type="primary"
              size="large"
              :loading="loading"
              :disabled="loading"
              class="w-full !rounded-[8px] !bg-[#0052d9] hover:!bg-[#003cab] hover:opacity-90 !border-none !h-[48px] !text-white font-medium tracking-wide transition-all shadow-[0_4px_12px_rgba(0,82,217,0.3)]"
              @click="submitForm"
            >
              登 录
            </el-button>
          </el-form-item>
        </el-form>

      </div>

      <!-- Right Decorative Section -->
      <div 
        class="hidden md:flex flex-1 relative bg-gradient-to-br from-[#f8fafc] to-[#e2e8f0] overflow-hidden items-center justify-center transition-all duration-700"
        :class="{ 'animate-on': isAnimating }"
      >
        <!-- Grid pattern background -->
        <div class="absolute inset-0 z-0 bg-[linear-gradient(to_right,#e5e7eb_1px,transparent_1px),linear-gradient(to_bottom,#e5e7eb_1px,transparent_1px)] bg-[size:4rem_4rem] opacity-40"></div>
        
        <!-- Decorative subtle background shapes -->
        <div class="absolute right-[-15%] top-[-5%] w-[800px] h-[800px] bg-white rounded-full opacity-50 mix-blend-overlay"></div>
        <div class="absolute left-[-10%] bottom-[-10%] w-[600px] h-[600px] bg-white rounded-full opacity-40 mix-blend-overlay border border-gray-100"></div>

        <!-- 3D style floating elements -->
        <!-- Primary Blue card -->
        <div class="card-primary absolute top-[30%] left-[22%] w-48 h-16 rounded-[14px] bg-gradient-to-r from-[#0052d9] to-[#3b82f6] shadow-[0_16px_32px_rgba(0,82,217,0.3)] transform -rotate-12 flex items-center justify-center text-white font-bold tracking-wider z-10 backdrop-blur-sm border border-blue-400/30 transition-transform duration-500">
          Primary
        </div>

        <!-- Secondary glass card -->
        <div class="card-secondary absolute top-[48%] left-[12%] w-44 h-14 rounded-[14px] bg-white/60 shadow-[0_16px_32px_rgba(0,0,0,0.06)] transform -rotate-12 flex items-center justify-center text-gray-400 font-bold tracking-wider z-10 backdrop-blur-xl border border-white transition-transform duration-500">
          Secondary
        </div>

        <!-- Big Logo Card -->
        <div class="card-logo absolute top-[28%] right-[22%] w-36 h-36 rounded-3xl bg-[#0052d9] shadow-[0_24px_48px_rgba(0,82,217,0.4)] transform rotate-12 flex items-center justify-center text-white text-7xl font-black z-20 bg-gradient-to-br from-[#3b82f6] to-[#0052d9] border border-blue-300/40 transition-transform duration-500">
          H
        </div>

        <!-- Floating glass circles layered effect -->
        <div class="glass-circle-1 absolute top-[38%] right-[42%] w-[72px] h-[72px] rounded-full bg-[#0052d9] shadow-2xl transform transition-transform duration-500 z-30"></div>
        <div class="glass-circle-2 absolute top-[48%] right-[45%] w-[88px] h-[88px] rounded-full bg-emerald-400/80 backdrop-blur-md shadow-2xl transform transition-transform duration-500 z-20 border border-white/50"></div>
        <div class="glass-circle-3 absolute top-[62%] right-[51%] w-[100px] h-[100px] rounded-full bg-white/70 backdrop-blur-xl shadow-[0_8px_24px_rgba(0,0,0,0.05)] transform transition-transform duration-500 z-10 border border-white"></div>
        
        <!-- large 'Ag' style text in background -->
        <div class="absolute right-12 top-[30%] text-[200px] font-black text-gray-300/20 tracking-tighter transform rotate-12 select-none pointer-events-none">
          Hy
        </div>

        <!-- Bottom right decorative toggle -->
        <div 
          @click="toggleAnimation"
          class="absolute bottom-16 right-24 w-16 h-8 rounded-full bg-gray-200 border border-white/80 shadow-inner flex items-center px-1 z-20 cursor-pointer transition-colors duration-300"
        >
          <div 
            class="w-6 h-6 rounded-full bg-[#0052d9] shadow-md transition-transform duration-300"
            :class="isAnimating ? 'translate-x-8' : 'translate-x-0'"
          ></div>
        </div>
      </div>
    </div>

    <!-- 底部版权信息 -->
    <div class="absolute bottom-4 left-0 right-0 z-50 pointer-events-none">
      <BottomInfo class="pointer-events-auto" />
    </div>

    <!-- 滑块验证码弹窗 -->
    <el-dialog
      v-model="slideDialogVisible"
      :show-close="false"
      :close-on-click-modal="false"
      :close-on-press-escape="true"
      width="350px"
      class="slide-captcha-dialog !p-0 !bg-transparent !shadow-none"
      align-center
      @closed="handleSlideDialogClosed"
    >
      <template #header>
        <span class="hidden">隐形头部</span>
      </template>
      <div class="flex justify-center bg-white rounded-2xl shadow-xl overflow-hidden p-3 relative">
        <div v-if="slideData.image && slideCaptchaId" :key="slideCaptchaId">
          <Slide
            :data="slideData"
            :events="slideEvents"
            :config="slideConfig"
          />
        </div>
        <div v-else class="py-12 w-[300px] text-center text-sm text-gray-400 flex items-center justify-center flex-col gap-2">
          <el-icon class="is-loading text-2xl text-blue-500"><Loading /></el-icon>
          <span>{{ slideLoading ? '验证码刷新中…' : '验证码加载中…' }}</span>
        </div>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
  import { onBeforeUnmount, onMounted, reactive, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import { getCaptcha, getSlideCaptcha, verifySlideCaptcha } from '@/api/user'
  import { useUserStore } from '@/pinia/modules/user'
  import { User, Lock, Loading } from '@element-plus/icons-vue'
  import { Slide } from 'go-captcha-vue'
  import 'go-captcha-vue/dist/style.css'
  import BottomInfo from '@/components/bottomInfo/bottomInfo.vue'

  // 后端 challenge TTL=3min，提前 30s 主动续杯，避免用户看到过期图还操作
  const SLIDE_CAPTCHA_PREEMPTIVE_REFRESH_MS = (3 * 60 - 30) * 1000

  defineOptions({
    name: 'PortalEntryPage'
  })

  const loading = ref(false)
  const currentYear = new Date().getFullYear()
  const rememberMe = ref(false)
  const isAnimating = ref(true)

  const toggleAnimation = () => {
    isAnimating.value = !isAnimating.value
  }

  const sanitizeLoginUrl = () => {
    if (typeof window === 'undefined') {
      return
    }
    const url = new URL(window.location.href)
    const sensitiveKeys = ['username', 'password', 'pass', 'pwd']
    let changed = false
    sensitiveKeys.forEach((key) => {
      if (url.searchParams.has(key)) {
        url.searchParams.delete(key)
        changed = true
      }
    })

    if (url.hash.includes('?')) {
      const [hashPath, hashQuery = ''] = url.hash.split('?')
      const hashSearchParams = new URLSearchParams(hashQuery)
      let hashChanged = false
      sensitiveKeys.forEach((key) => {
        if (hashSearchParams.has(key)) {
          hashSearchParams.delete(key)
          hashChanged = true
        }
      })
      if (hashChanged) {
        const cleanHashQuery = hashSearchParams.toString()
        url.hash = `${hashPath}${cleanHashQuery ? `?${cleanHashQuery}` : ''}`
        changed = true
      }
    }

    if (changed) {
      const query = url.searchParams.toString()
      const cleanUrl = `${url.origin}${url.pathname}${query ? `?${query}` : ''}${url.hash}`
      window.history.replaceState({}, '', cleanUrl)
    }
  }

  // 验证函数
  const checkUsername = (rule, value, callback) => {
    if (value.length < 5) {
      return callback(new Error('请输入正确的账号（至少5位）'))
    } else {
      callback()
    }
  }
  const checkPassword = (rule, value, callback) => {
    if (value.length < 6) {
      return callback(new Error('请输入正确的密码（至少6位）'))
    } else {
      callback()
    }
  }
  // 登录相关操作
  const loginForm = ref(null)
  const loginFormData = reactive({
    username: '',
    password: '',
    slideToken: ''
  })
  const rules = reactive({
    username: [{ validator: checkUsername, trigger: 'blur' }],
    password: [{ validator: checkPassword, trigger: 'blur' }]
  })

  // 滑块验证码状态
  const slideDialogVisible = ref(false)
  const slideCaptchaId = ref('')
  const slideLoading = ref(false)
  const slideData = reactive({
    image: '',
    thumb: '',
    thumbX: 0,
    thumbY: 0,
    thumbWidth: 0,
    thumbHeight: 0
  })
  const slideConfig = reactive({
    width: 300,
    height: 220,
    verticalPadding: 16,
    horizontalPadding: 12,
    showTheme: true,
    title: '安全验证'
  })
  const slideConfirming = ref(false)
  let slideRefreshTimer = null
  // 并发计数，保证后到的 loadSlideCaptcha 结果覆盖前一次请求（防闪回旧图）
  let slideLoadSeq = 0

  const userStore = useUserStore()

  const clearSlideRefreshTimer = () => {
    if (slideRefreshTimer) {
      clearTimeout(slideRefreshTimer)
      slideRefreshTimer = null
    }
  }

  const scheduleSlideRefresh = () => {
    clearSlideRefreshTimer()
    slideRefreshTimer = setTimeout(() => {
      // 过期前抢先续杯；仅当弹窗仍开着时才刷新
      if (slideDialogVisible.value && !slideConfirming.value) {
        loadSlideCaptcha().catch(() => {})
      }
    }, SLIDE_CAPTCHA_PREEMPTIVE_REFRESH_MS)
  }

  const resetSlideData = () => {
    slideData.image = ''
    slideData.thumb = ''
    slideData.thumbX = 0
    slideData.thumbY = 0
    slideData.thumbWidth = 0
    slideData.thumbHeight = 0
  }

  const loadSlideCaptcha = async () => {
    if (slideLoading.value) {
      return false
    }
    const seq = ++slideLoadSeq
    slideLoading.value = true
    // 立即清空旧 captchaId，触发 :key 变化，卸载旧 Slide，防止内部状态残留（stale drag 位置 / 事件监听）
    slideCaptchaId.value = ''
    resetSlideData()
    try {
      const res = await getSlideCaptcha()
      // 被更新的后续请求覆盖，则丢弃当前结果
      if (seq !== slideLoadSeq) {
        return false
      }
      if (!res || res.code !== 0 || !res.data) {
        ElMessage({
          type: 'warning',
          message: (res && res.msg) || '验证码加载失败，请稍后重试',
          duration: 2200,
          showClose: false
        })
        return false
      }
      slideData.image = res.data.masterBase64
      slideData.thumb = res.data.thumbBase64
      slideData.thumbX = 0
      slideData.thumbY = Number(res.data.thumbY || 0)
      slideData.thumbWidth = Number(res.data.thumbWidth || 0)
      slideData.thumbHeight = Number(res.data.thumbHeight || 0)
      // 最后再赋 captchaId，确保模板里 `v-if="slideData.image && slideCaptchaId"` 一次性拿到完整数据后再挂 Slide
      slideCaptchaId.value = res.data.captchaId
      scheduleSlideRefresh()
      return true
    } catch (err) {
      if (seq === slideLoadSeq) {
        ElMessage({
          type: 'warning',
          message: '验证码加载失败，请检查网络后重试',
          duration: 2200,
          showClose: false
        })
      }
      return false
    } finally {
      if (seq === slideLoadSeq) {
        slideLoading.value = false
      }
    }
  }

  const openSlideDialog = async () => {
    const ok = await loadSlideCaptcha()
    if (!ok) {
      // 加载失败直接结束登录 loading 态，避免按钮转圈转死
      loading.value = false
      return
    }
    slideDialogVisible.value = true
  }

  const handleSlideDialogClosed = () => {
    clearSlideRefreshTimer()
    if (!slideConfirming.value && !loginFormData.slideToken) {
      loading.value = false
    }
  }

  const slideEvents = {
    refresh: () => {
      // go-captcha-vue 的 refresh 回调是同步调用，内部紧跟着会把 dragLeft 归零；
      // 这里不 await，交给 loadSlideCaptcha 自己用 seq 做去重，避免卡住内部重置逻辑
      loadSlideCaptcha().catch(() => {})
    },
    close: () => {
      slideDialogVisible.value = false
    },
    confirm: async (point, reset) => {
      if (slideConfirming.value) return
      if (!slideCaptchaId.value) {
        // 还在刷新中用户就松手，直接忽略这次提交
        reset && reset()
        return
      }
      slideConfirming.value = true
      try {
        const res = await verifySlideCaptcha({
          captchaId: slideCaptchaId.value,
          x: Math.round(point.x)
        })
        if (!res || res.code !== 0 || !res.data?.slideToken) {
          // 拦截器已经 toast 过一次业务错误；此处只负责拉新图
          await loadSlideCaptcha()
          reset && reset()
          return
        }
        loginFormData.slideToken = res.data.slideToken
        clearSlideRefreshTimer()
        slideDialogVisible.value = false
        await performLogin()
      } catch (err) {
        await loadSlideCaptcha()
        reset && reset()
      } finally {
        slideConfirming.value = false
      }
    }
  }

  const performLogin = async () => {
    loading.value = true
    try {
      const flag = await userStore.LoginIn(loginFormData)
      if (!flag) {
        loginFormData.slideToken = ''
      } else {
        if (rememberMe.value) {
          window.localStorage.setItem('heyutech_login_info', JSON.stringify({
            username: loginFormData.username,
            password: loginFormData.password
          }))
        } else {
          window.localStorage.removeItem('heyutech_login_info')
        }
      }
    } catch (e) {
      loginFormData.slideToken = ''
    } finally {
      loading.value = false
    }
  }

  // 问一次后端当前是否需要验证码。
  //   - 后端 /auth/captcha 基于 shouldOpenCaptcha(ip) 返回 openCaptcha:
  //       * open-captcha < 0：管理员主动关闭验证码 → false
  //       * open-captcha == 0：每次都要 → true
  //       * open-captcha > 0：同 IP 失败次数达到阈值才要 → 动态
  //   - 请求失败时出于安全考虑回退到"需要验证码"
  const isCaptchaRequired = async () => {
    try {
      const res = await getCaptcha()
      if (res?.code === 0 && res.data && res.data.openCaptcha === false) {
        return false
      }
    } catch (e) {
      // 保持静默：下游弹滑块即可
    }
    return true
  }

  const submitForm = async (event) => {
    event?.preventDefault?.()
    event?.stopPropagation?.()
    await loginForm.value.validate(async (v) => {
      if (!v) {
        ElMessage({ type: 'warning', message: '请完善账号和密码', duration: 1800, showClose: false })
        return false
      }
      loginFormData.slideToken = ''
      loading.value = true
      const required = await isCaptchaRequired()
      if (!required) {
        await performLogin()
        return
      }
      await openSlideDialog()
    })
  }

  onMounted(() => {
    sanitizeLoginUrl()
    try {
      const saved = window.localStorage.getItem('heyutech_login_info')
      if (saved) {
        const info = JSON.parse(saved)
        loginFormData.username = info.username || ''
        loginFormData.password = info.password || ''
        if (info.username || info.password) {
          rememberMe.value = true
        }
      }
    } catch (e) {
      // ignore
    }
  })

  onBeforeUnmount(() => {
    clearSlideRefreshTimer()
  })
</script>

<style scoped>
/* 经典无边框极简设计：高定扁平化色系 */
:deep(.login-input .el-input__wrapper) {
  border-radius: 8px !important;
  background-color: #f3f4f6 !important;
  box-shadow: 0 0 0 1px transparent inset !important; 
  padding: 0 16px !important;
  transition: all 0.2s ease !important;
}

:deep(.login-input .el-input__wrapper:hover) {
  box-shadow: 0 0 0 1px #e5e7eb inset !important;
  background-color: #f9fafb !important;
}

:deep(.login-input .el-input__wrapper.is-focus) {
  box-shadow: 0 0 0 1.5px #0052d9 inset !important;
  background-color: #ffffff !important;
}

:deep(.login-input .el-input__inner) {
  color: #1a1a1a; 
  font-weight: 500;
}

:deep(.el-checkbox__input.is-checked .el-checkbox__inner) {
  background-color: #0052d9;
  border-color: #0052d9;
}

:deep(.el-checkbox__input.is-checked + .el-checkbox__label) {
  color: #1a1a1a;
}

/* 滑块弹窗 */
:deep(.slide-captcha-dialog .el-dialog) {
  border-radius: 18px;
  padding: 0;
  overflow: hidden;
}

:deep(.slide-captcha-dialog .el-dialog__header) {
  margin-right: 0;
  padding: 18px 20px 8px;
}

:deep(.slide-captcha-dialog .el-dialog__title) {
  font-size: 16px;
  font-weight: 600;
  color: #1d1d1f;
}

:deep(.slide-captcha-dialog .el-dialog__header) {
  display: none !important;
}
:deep(.slide-captcha-dialog .el-dialog__body) {
  padding: 0 !important;
  background: transparent !important;
}

@keyframes float1 {
  0%, 100% { transform: translateY(0) scale(1) rotate(-12deg); }
  50% { transform: translateY(-15px) scale(1.05) rotate(-6deg); }
}
@keyframes float2 {
  0%, 100% { transform: translateY(0) scale(1) rotate(12deg); }
  50% { transform: translateY(-20px) scale(1.05) rotate(16deg); }
}
@keyframes float3 {
  0%, 100% { transform: translateY(0) scale(1); }
  50% { transform: translateY(-25px) scale(1.1); }
}

.animate-on .card-primary {
  animation: float1 4s ease-in-out infinite !important;
}
.animate-on .card-secondary {
  animation: float1 5s ease-in-out infinite reverse !important;
}
.animate-on .card-logo {
  animation: float2 6s ease-in-out infinite !important;
}
.animate-on .glass-circle-1 {
  animation: float3 3s ease-in-out infinite !important;
}
.animate-on .glass-circle-2 {
  animation: float3 4.5s ease-in-out infinite reverse !important;
}
.animate-on .glass-circle-3 {
  animation: float3 6s ease-in-out infinite !important;
}
</style>
