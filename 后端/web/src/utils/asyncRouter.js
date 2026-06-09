import {
  namedComponentIds,
  normalizeComponentId,
  resolveComponentLoader,
  resolveComponentCacheKey
} from '@/utils/componentRegistry'

export const asyncRouterHandle = (asyncRouter) => {
  asyncRouter.forEach((item) => {
    if (item.component && typeof item.component === 'string') {
      const componentId = normalizeComponentId(item.component) || namedComponentIds.error
      item.meta = item.meta || {}
      item.component = dynamicImport(componentId)
      item.meta.componentId = componentId
      item.meta.cacheKey = resolveComponentCacheKey(componentId)
    }
    if (item.children) {
      asyncRouterHandle(item.children)
    }
  })
}

function dynamicImport(componentId) {
  const cacheKey = resolveComponentCacheKey(componentId)
  const fallbackComponentId = namedComponentIds.error
  const loader = resolveComponentLoader(componentId) || resolveComponentLoader(fallbackComponentId)

  return async () => {
    const module = await loader()
    const component = module?.default || module
    if (component && typeof component === 'object' && cacheKey) {
      component.name = cacheKey
    }
    return module
  }
}
