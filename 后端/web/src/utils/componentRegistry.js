import {
  componentRegistry,
  namedComponentIds
} from '@/componentRegistry.generated'

const COMPONENT_ID_PATTERN = /^cmp_[0-9a-f]{16}$/i
const reservedComponentIds = new Set(Object.values(namedComponentIds))

const sanitizeComponentIdValue = (value = '') => {
  let normalized = String(value || '').trim().replace(/\\/g, '/')
  normalized = normalized.replace(/^\/+/, '')
  if (normalized.startsWith('src/')) {
    normalized = normalized.slice(4)
  }
  return normalized
}

export const normalizeComponentId = (value = '') => {
  const normalized = sanitizeComponentIdValue(value)
  if (!normalized) {
    return ''
  }
  if (COMPONENT_ID_PATTERN.test(normalized)) {
    return normalized.toLowerCase()
  }
  return ''
}

export const getComponentEntry = (value = '') => {
  const componentId = normalizeComponentId(value)
  return componentRegistry[componentId] || componentRegistry[namedComponentIds.error] || null
}

export const resolveComponentLoader = (value = '') => {
  return getComponentEntry(value)?.loader || null
}

export const resolveComponentCacheKey = (value = '') => {
  const componentId = normalizeComponentId(value)
  if (!componentId) {
    return ''
  }
  return `slot_${componentId.slice(4)}`
}

export const getComponentOptions = () => {
  return Object.keys(componentRegistry)
    .filter((componentId) => !reservedComponentIds.has(componentId))
    .sort()
    .map((componentId) => ({
      value: componentId,
      label: `页面槽位 · ${componentId.slice(-6)}`
    }))
}

export { namedComponentIds }
