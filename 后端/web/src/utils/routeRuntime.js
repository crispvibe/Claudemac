import router, { adminLayoutPath } from '@/router'

const isExternalUrl = (val) => {
  return typeof val === 'string' && /^(https?:)?\/\//.test(val)
}

const normalizeAbsolutePath = (pathValue) => {
  const raw = '/' + String(pathValue || '')
  return raw.replace(/\/+/g, '/')
}

const normalizeRelativePath = (pathValue) => {
  return String(pathValue || '').replace(/^\/+/, '')
}

const createRouteRecord = (route, path) => {
  const nextRoute = { ...route, path }
  delete nextRoute.children
  delete nextRoute.parent
  return nextRoute
}

const addTopLevelIfAbsent = (routeRecord) => {
  if (routeRecord?.name && !router.hasRoute(routeRecord.name)) {
    router.addRoute(routeRecord)
  }
}

const registerSectionRoot = (route, segments) => {
  const firstChild = route.children?.[0]
  if (!firstChild || !route?.name || router.hasRoute(route.name)) {
    return
  }
  const fullParentPath = [...segments, route.path].filter(Boolean).join('/')
  const redirectPath = normalizeRelativePath(
    [fullParentPath, firstChild.path].filter(Boolean).join('/')
  )
  router.addRoute('layout', {
    path: normalizeRelativePath(fullParentPath),
    name: route.name,
    meta: route.meta,
    redirect: `${adminLayoutPath}/${redirectPath}`
  })
}

const addRouteByChildren = (route, segments = [], parentName = null) => {
  if (isExternalUrl(route?.path) || isExternalUrl(route?.name) || isExternalUrl(route?.component)) {
    return
  }

  if (route?.name === 'layout') {
    route.children?.forEach((child) => addRouteByChildren(child, [], null))
    return
  }

  if (route?.meta?.defaultMenu === true && parentName === null) {
    const children = route.children ? [...route.children] : []
    const newRoute = createRouteRecord(
      route,
      normalizeAbsolutePath([...segments, route.path].filter(Boolean).join('/'))
    )
    if (router.hasRoute(newRoute.name)) {
      return
    }
    addTopLevelIfAbsent(newRoute)
    if (children.length) {
      children.forEach((child) => addRouteByChildren(child, [], newRoute.name))
    }
    return
  }

  if (route?.children?.length) {
    if (!parentName) {
      registerSectionRoot(route, segments)
    }
    const nextSegments = isExternalUrl(route.path) ? segments : [...segments, route.path]
    route.children.forEach((child) => addRouteByChildren(child, nextSegments, parentName))
    return
  }

  const newRoute = createRouteRecord(
    route,
    normalizeRelativePath([...segments, route.path].filter(Boolean).join('/'))
  )

  if (parentName) {
    if (!router.hasRoute(parentName)) {
      return
    }
    router.addRoute(parentName, newRoute)
    return
  }

  router.addRoute('layout', newRoute)
}

export const collectRoutesToRegister = (baseRouters = []) => {
  const toRegister = []
  const layoutRoute = baseRouters[0]
  if (layoutRoute?.children?.length) {
    toRegister.push(...layoutRoute.children)
  }
  if (baseRouters.length > 1) {
    baseRouters.slice(1).forEach((route) => {
      if (route?.name !== 'layout') {
        toRegister.push(route)
      }
    })
  }
  return {
    layoutRoute,
    toRegister
  }
}

export const registerDynamicRoutes = (baseRouters = []) => {
  const { layoutRoute, toRegister } = collectRoutesToRegister(baseRouters)
  if (layoutRoute?.name === 'layout' && !router.hasRoute('layout')) {
    router.addRoute({ ...layoutRoute, path: adminLayoutPath, children: [] })
  }
  toRegister.forEach((routeRecord) => addRouteByChildren(routeRecord, [], null))
}
