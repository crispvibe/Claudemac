import { asyncRouterHandle } from '@/utils/asyncRouter'
import { emitter } from '@/utils/event-bus.js'
import { fetchNavigationRoutes } from '@/api/navigation'
import { defineStore } from 'pinia'
import { ref, watchEffect } from 'vue'
import { namedComponentIds } from '@/utils/componentRegistry'
import router, { adminLayoutPath, adminBasePath } from '@/router'
import { config } from '@/core/config.js'

const notLayoutRouterArr = []
const keepAliveRoutersArr = []
const nameMap = {}

const resetArray = (arr) => {
  arr.splice(0, arr.length)
}

const resetObject = (obj) => {
  Object.keys(obj).forEach((key) => {
    delete obj[key]
  })
}

const formatRouter = (routes, routeMap, parent) => {
  routes &&
    routes.forEach((item) => {
      item.parent = parent
      item.meta.btns = item.btns
      item.meta.hidden = item.hidden
      if (item.meta.defaultMenu === true) {
        if (!parent) {
          // defaultMenu 作为顶级路由挂在 layout 之外，也需要带上 slug 前缀
          // 避免访问 /#/dashboard 这类裸路径落到 404
          item = { ...item, path: `${adminBasePath}/${item.path}` }
          notLayoutRouterArr.push(item)
        }
      }
      routeMap[item.name] = item
      if (item.children && item.children.length > 0) {
        formatRouter(item.children, routeMap, item)
      }
    })
}

const KeepAliveFilter = (routes) => {
  routes &&
    routes.forEach((item) => {
      // 子菜单中有 keep-alive 的，父菜单也必须 keep-alive，否则无效。这里将子菜单中有 keep-alive 的父菜单也加入。
      if (
        (item.children && item.children.some((ch) => ch.meta.keepAlive)) ||
        item.meta.keepAlive
      ) {
        const cacheKey = item.meta.cacheKey
        if (cacheKey) {
          keepAliveRoutersArr.push(cacheKey)
          nameMap[item.name] = cacheKey
        }
      }
      if (item.children && item.children.length > 0) {
        KeepAliveFilter(item.children)
      }
    })
}

export const useRouterStore = defineStore('router', () => {
  const keepAliveRouters = ref([])
  const asyncRouterFlag = ref(0)
  const setKeepAliveRouters = (history) => {
    const keepArrTemp = []
    
    // 1. 首先添加原有的keepAlive配置
    keepArrTemp.push(...keepAliveRoutersArr)
    if (config.keepAliveTabs) {
      history.forEach((item) => {
        const routeInfo = routeMap[item.name]
        if (routeInfo && routeInfo.meta) {
          const cacheKey = routeInfo.meta.cacheKey
          if (cacheKey) {
            keepArrTemp.push(cacheKey)
          }
        }
        
        // 3. 如果子路由在tabs中打开，父路由也需要keepAlive
        if (nameMap[item.name]) {
          keepArrTemp.push(nameMap[item.name])
        }
      })
    }
    keepAliveRouters.value = Array.from(new Set(keepArrTemp))
  }

  // 处理组件缓存
  const handleKeepAlive = async (to, depth = 0) => {
    if (!to.matched.some((item) => item.meta.keepAlive)) return
    if (depth > 10) return

    if (to.matched?.length > 2) {
      for (let i = 1; i < to.matched.length; i++) {
        const element = to.matched[i - 1]

        if (element.name === 'layout') {
          to.matched.splice(i, 1)
          await handleKeepAlive(to, depth + 1)
          continue
        }

        if (typeof element.components.default === 'function') {
          await element.components.default()
          await handleKeepAlive(to, depth + 1)
        }
      }
    }
  }


  emitter.on('setKeepAlive', setKeepAliveRouters)

  const asyncRouters = ref([])

  const topMenu = ref([])

  const leftMenu = ref([])

  const menuMap = {}

  const topActive = ref('')

  const setLeftMenu = (name) => {
    sessionStorage.setItem('topActive', name)
    topActive.value = name
    leftMenu.value = []
    if (menuMap[name]?.children) {
      leftMenu.value = menuMap[name].children
    }
    return menuMap[name]?.children
  }

  const findTopActive = (menuMap, routeName) => {
    for (let topName in menuMap) {
      const topItem = menuMap[topName];
      if (topItem.children?.some(item => item.name === routeName)) {
        return topName;
      }
      const foundName = findTopActive(topItem.children || {}, routeName);
      if (foundName) {
        return topName;
      }
    }
    return null;
  };

  watchEffect(() => {
    let topActiveName = sessionStorage.getItem('topActive')
    const currentRouteName = router.currentRoute.value?.name
    const topLevelChildren = asyncRouters.value[0]?.children || []
    // 初始化菜单内容，防止重复添加
    topMenu.value = []
    resetObject(menuMap)
    topLevelChildren.forEach((item) => {
      if (item.hidden) return
      menuMap[item.name] = item
      topMenu.value.push({ ...item, children: [] })
    })
    if (!topActiveName || topActiveName === 'undefined' || topActiveName === 'null') {
      topActiveName = findTopActive(menuMap, currentRouteName)
    }
    setLeftMenu(topActiveName)
  })

  const routeMap = {}
  // 从后台获取动态路由
  const SetAsyncRouter = async () => {
    asyncRouterFlag.value++
    resetArray(notLayoutRouterArr)
    resetArray(keepAliveRoutersArr)
    resetObject(nameMap)
    resetObject(routeMap)
    const baseRouter = [
      {
        path: adminLayoutPath,
        name: 'layout',
        component: namedComponentIds.layout,
        meta: {
          title: '布局容器'
        },
        children: []
      }
    ]
    const asyncRouterRes = await fetchNavigationRoutes()
    const asyncRouter = asyncRouterRes.data.menus
    asyncRouter &&
      asyncRouter.push({
        path: 'reload',
        name: 'Reload',
        hidden: true,
        meta: {
          title: '',
          closeTab: true
        },
        component: namedComponentIds.reload
      })
    formatRouter(asyncRouter, routeMap)
    baseRouter[0].children = asyncRouter
    if (notLayoutRouterArr.length !== 0) {
      baseRouter.push(...notLayoutRouterArr)
    }
    asyncRouterHandle(baseRouter)
    KeepAliveFilter(asyncRouter)
    asyncRouters.value = baseRouter
    return true
  }

  return {
    topActive,
    setLeftMenu,
    topMenu,
    leftMenu,
    asyncRouters,
    keepAliveRouters,
    asyncRouterFlag,
    SetAsyncRouter,
    routeMap,
    handleKeepAlive
  }
})
