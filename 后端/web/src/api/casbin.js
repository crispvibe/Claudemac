import service from '@/utils/request'
export const updateRolePolicies = (data) => {
  return service({
    url: '/role-policies/update',
    method: 'post',
    data
  })
}

export const fetchRolePolicyPaths = (data) => {
  return service({
    url: '/role-policies/by-role',
    method: 'post',
    data
  })
}
