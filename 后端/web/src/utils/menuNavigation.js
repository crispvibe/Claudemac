import router, { adminLayoutPath } from '@/router'

export const isExternalRouteName = (value = '') => {
  return typeof value === 'string' && /^(https?:)?\/\//.test(value)
}

export const isFrameRoute = (route) => {
  return typeof route?.path === 'string' && route.path.endsWith('/iframe')
}

export const isFrameRouteRecord = (routeRecord) => {
  if (!routeRecord || typeof routeRecord !== 'object') {
    return false
  }
  const routePath = String(routeRecord.path || '')
  return routePath === 'iframe' || routePath.endsWith('/iframe')
}

export const buildRoutePayload = (routeMap, routeName) => {
  const query = {}
  const params = {}
  routeMap?.[routeName]?.parameters?.forEach((item) => {
    if (item.type === 'query') {
      query[item.key] = item.value
    } else {
      params[item.key] = item.value
    }
  })
  return {
    name: routeName,
    query,
    params
  }
}

export const resolveActiveMenuKey = (route) => {
  if (isFrameRoute(route) && route?.query?.url) {
    return decodeURIComponent(route.query.url)
  }
  return route?.meta?.activeName || route?.name || ''
}

export const navigateByMenuName = ({
  routeName,
  currentRouteName,
  routeMap,
  fallbackPath = `${adminLayoutPath}/iframe`
}) => {
  if (!routeName || routeName === currentRouteName) {
    return false
  }

  if (isExternalRouteName(routeName)) {
    return false
  }

  if (isFrameRouteRecord(routeMap?.[routeName])) {
    router.push({ path: fallbackPath })
    return true
  }

  router.push(buildRoutePayload(routeMap, routeName))
  return true
}
