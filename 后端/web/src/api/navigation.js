import service from '@/utils/request'

export const fetchNavigationRoutes = () => {
  return service({
    url: '/navigation/routes',
    method: 'post'
  })
}

export const fetchNavigationList = (data) => {
  return service({
    url: '/navigation/list',
    method: 'post',
    data
  })
}

export const createNavigationItem = (data) => {
  return service({
    url: '/navigation/create',
    method: 'post',
    data
  })
}

export const fetchNavigationTree = () => {
  return service({
    url: '/navigation/tree',
    method: 'post'
  })
}

export const assignRoleNavigation = (data) => {
  return service({
    url: '/navigation/assign-role',
    method: 'post',
    data
  })
}

export const fetchRoleNavigation = (data) => {
  return service({
    url: '/navigation/role-tree',
    method: 'post',
    data
  })
}

export const removeNavigationItem = (data) => {
  return service({
    url: '/navigation/delete',
    method: 'post',
    data
  })
}

export const updateNavigationItem = (data) => {
  return service({
    url: '/navigation/update',
    method: 'post',
    data
  })
}

export const fetchNavigationDetail = (data) => {
  return service({
    url: '/navigation/detail',
    method: 'post',
    data
  })
}
