import service from '@/utils/request'

export const fetchRoleList = (data) => {
  return service({
    url: '/roles/list',
    method: 'post',
    data
  })
}

export const removeRole = (data) => {
  return service({
    url: '/roles/delete',
    method: 'post',
    data
  })
}

export const createRole = (data) => {
  return service({
    url: '/roles/create',
    method: 'post',
    data
  })
}

export const cloneRole = (data) => {
  return service({
    url: '/roles/copy',
    method: 'post',
    data
  })
}

export const updateRoleDataScope = (data) => {
  return service({
    url: '/roles/data-scope',
    method: 'post',
    data
  })
}

export const updateRole = (data) => {
  return service({
    url: '/roles/update',
    method: 'put',
    data
  })
}
