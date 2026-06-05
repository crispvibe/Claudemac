import { login, getUserInfo } from '@/api/user'
import { jsonInBlacklist } from '@/api/jwt'
import router, { adminLoginPath } from '@/router/index'
import { ElLoading, ElMessage } from 'element-plus'
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { useRouterStore } from './router'
import { registerDynamicRoutes } from '@/utils/routeRuntime'

import { useAppStore } from '@/pinia'

export const useUserStore = defineStore('user', () => {
  const appStore = useAppStore()
  const loadingInstance = ref(null)

  const userInfo = ref({
    uuid: '',
    nickName: '',
    headerImg: '',
    primaryRole: {}
  })
  const hasSession = ref(sessionStorage.getItem('hasSession') === 'true')
  const token = computed(() => '')
  const currentToken = computed(() => '')

  const setUserInfo = (val) => {
    userInfo.value = val
    hasSession.value = true
    sessionStorage.setItem('hasSession', 'true')
    if (val.originSetting) {
      Object.keys(appStore.config).forEach((key) => {
        if (val.originSetting[key] !== undefined) {
          appStore.config[key] = val.originSetting[key]
        }
      })
    }
  }

  const setToken = () => {
    hasSession.value = true
    sessionStorage.setItem('hasSession', 'true')
  }

  const ResetUserInfo = (value = {}) => {
    userInfo.value = {
      ...userInfo.value,
      ...value
    }
  }
  /* 获取用户信息*/
  const GetUserInfo = async (options = {}) => {
    const res = await getUserInfo(options)
    if (res.code === 0) {
      setUserInfo(res.data.userInfo)
      hasSession.value = true
    }
    return res
  }
  /* 登录*/
  const LoginIn = async (loginInfo) => {
    try {
      loadingInstance.value = ElLoading.service({
        fullscreen: true,
        text: '登录中，请稍候...'
      })

      const res = await login(loginInfo)

      if (res.code !== 0) {
        return false
      }
      // 登陆成功，设置用户信息和权限相关信息
      setUserInfo(res.data.user)
      setToken()

      // 初始化路由信息
      const routerStore = useRouterStore()
      await routerStore.SetAsyncRouter()
      registerDynamicRoutes(routerStore.asyncRouters || [])

      if(router.currentRoute.value.query.redirect) {
        await router.replace(router.currentRoute.value.query.redirect)
        return true
      }

      if (!router.hasRoute(userInfo.value.primaryRole.defaultEntry)) {
        ElMessage.error('不存在可以登陆的首页，请联系管理员进行配置')
      } else {
        await router.replace({ name: userInfo.value.primaryRole.defaultEntry })
      }

      // 全部操作均结束，关闭loading并返回
      return true
    } catch (error) {
      console.error('LoginIn error:', error)
      return false
    } finally {
      loadingInstance.value?.close()
    }
  }
  /* 登出*/
  const LoginOut = async () => {
    const res = await jsonInBlacklist()

    // 登出失败
    if (res.code !== 0) {
      return
    }

    await ClearStorage()

    // 先把 hash 硬切到登录页，再 reload。
    // 不能只 router.push 后立即 reload：push 是异步的，reload 可能在 hash 切换前触发，
    // 结果浏览器带着旧的 /layout/xxx 地址重新加载，命中 catchAll 直接展示 404。
    const target = `${window.location.origin}${window.location.pathname}${window.location.search}#${adminLoginPath}`
    window.location.replace(target)
    window.location.reload()
  }
  /* 清理数据 */
  const ClearStorage = async () => {
    hasSession.value = false
    sessionStorage.removeItem('hasSession')
    sessionStorage.clear()
    // 清理所有相关的localStorage项
    localStorage.removeItem('originSetting')
  }

  return {
    hasSession,
    userInfo,
    token,
    currentToken,
    GetUserInfo,
    LoginIn,
    ResetUserInfo,
    setUserInfo,
    setToken,
    LoginOut,
    loadingInstance,
    ClearStorage
  }
})
