import service from '@/utils/request'

export const getRoleButtonBindings = (data) => {
  return service({
    url: '/role-buttons/bindings',
    method: 'post',
    data
  })
}

export const saveRoleButtonBindings = (data) => {
  return service({
    url: '/role-buttons/bindings/update',
    method: 'post',
    data
  })
}

export const checkRoleButtonRemoval = (params) => {
  return service({
    url: '/role-buttons/bindings/removal-check',
    method: 'post',
    params
  })
}
