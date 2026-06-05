import { useUserStore } from '@/pinia/modules/user'
import { useRouterStore } from '@/pinia/modules/router'
import getPageTitle from '@/utils/page'
import { registerDynamicRoutes } from '@/utils/routeRuntime'
import router, { adminLayoutPath } from '@/router'
import Nprogress from 'nprogress'
import 'nprogress/nprogress.css'

// 配置 NProgress
Nprogress.configure({
  showSpinner: false,
  ease: 'ease',
  speed: 500
})

// 白名单路由
// NotFound 也放入白名单，避免未登录用户命中未知路径时再次触发鉴权探测
const PUBLIC_ROUTE_NAMES = ['Login', 'NotFound']

// 处理路由加载
const setupRouter = async (userStore) => {
  try {
    const routerStore = useRouterStore()
    // silentError: true 让 axios 拦截器遇到 401 时不 toast、不自动跳 Login，
    // 避免首次进入 / 登录页时反复触发"未登录或非法访问"提示以及路由死循环
    const userRes = await userStore.GetUserInfo({ silentError: true, donNotShowLoading: true })
    if (userRes?.code !== 0) {
      return false
    }
    await routerStore.SetAsyncRouter()
    registerDynamicRoutes(routerStore.asyncRouters || [])
    return true
  } catch (error) {
    console.error('Setup router failed:', error)
    return false
  }
}

const hasAuthSession = (userStore) => {
  return !!userStore.hasSession
}

const takePendingHomeFlag = () => {
  const shouldRedirect = sessionStorage.getItem('needToHome') === 'true'
  if (shouldRedirect) {
    sessionStorage.removeItem('needToHome')
  }
  return shouldRedirect
}

const getDefaultRouteName = (userStore) => {
  return userStore.userInfo?.primaryRole?.defaultEntry || ''
}

// 移除加载动画
const removeLoading = () => {
  const element = document.getElementById('app-boot-shell')
  element?.remove()
}

// 路由守卫
router.beforeEach(async (to, from) => {
  const userStore = useUserStore()
  const routerStore = useRouterStore()
  let hasSession = hasAuthSession(userStore)

  Nprogress.start()

  // 处理元数据和缓存
  to.meta.matched = [...to.matched]
  await routerStore.handleKeepAlive(to)
  // 设置页面标题
  document.title = getPageTitle(to.meta.title, to)
  // NotFound 必须走守卫兜底（跳登录或跳默认入口），其他纯客户端路由直接放行
  if (to.meta.client && to.name !== 'NotFound') {
    return true
  }

  // 统一的兜底跳转策略：
  //   - 已登录 → 跳当前角色的默认入口，失败再降级到 layout 根
  //   - 未登录 → 跳登录页
  const redirectToHome = () => {
    const defaultRouteName = getDefaultRouteName(userStore)
    if (defaultRouteName && router.hasRoute(defaultRouteName)) {
      return { name: defaultRouteName, replace: true }
    }
    return { path: adminLayoutPath, replace: true }
  }
  const redirectToLogin = () => ({ name: 'Login', replace: true })

  // 白名单路由处理（Login / NotFound）
  if (PUBLIC_ROUTE_NAMES.includes(to.name)) {
    if (!hasSession) {
      const recovered = await setupRouter(userStore)
      if (recovered) {
        userStore.setToken()
        hasSession = true
      }
    }
    if (hasSession) {
      if (!routerStore.asyncRouterFlag) {
        const ready = await setupRouter(userStore)
        if (!ready) {
          await userStore.ClearStorage()
          // 已登录态异常失效，统一回登录页，而不是展示 NotFound
          return to.name === 'Login' ? true : redirectToLogin()
        }
      }
      // 已登录访问 Login，一律回默认入口
      if (to.name === 'Login') {
        return redirectToHome()
      }
      // 已登录刷新时命中 NotFound：很可能是异步路由尚未注册导致 URL 被 catchAll 兜底。
      // 异步路由注册完成后用 fullPath 重新解析：若实际能匹配到业务页，保持用户停留在原页面；
      // 否则才视为真正的 404（菜单已删除、URL 打错），回默认入口。
      const resolved = router.resolve(to.fullPath)
      if (resolved.matched.length && resolved.name !== 'NotFound') {
        return { path: resolved.path, query: resolved.query, hash: resolved.hash, replace: true }
      }
      return redirectToHome()
    }
    // 未登录：Login 展示登录页；NotFound（退出后残留 URL、扫描器、手打错）统一跳 Login
    if (to.name === 'NotFound') {
      return redirectToLogin()
    }
    return true
  }

  // 需要登录的路由处理
  if (!hasSession) {
    const recovered = await setupRouter(userStore)
    if (recovered) {
      userStore.setToken()
      hasSession = true
      return to
    }
  }

  if (hasSession) {
    // 处理需要跳转到首页的情况
    if (takePendingHomeFlag()) {
      return redirectToHome()
    }

    // 处理异步路由
    if (!routerStore.asyncRouterFlag && !PUBLIC_ROUTE_NAMES.includes(from.name)) {
      const ready = await setupRouter(userStore)
      if (!ready) {
        await userStore.ClearStorage()
        return redirectToLogin()
      }
      return to
    }

    // 未匹配到任何业务路由（URL 打错、菜单已删除等）→ 回默认入口，不展示 404
    if (!to.matched.length) {
      return redirectToHome()
    }
    return true
  }

  // 未登录访问业务路由 → 统一跳登录页，不再展示 NotFound 隐匿页
  return redirectToLogin()
})

// 路由加载完成
router.afterEach(() => {
  document.querySelector('#scene-loader-anchor')?.scrollTo(0, 0)
  Nprogress.done()
})

// 路由错误处理
router.onError((error) => {
  console.error('Router error:', error)
  Nprogress.remove()
})

// 移除初始加载动画
removeLoading()
