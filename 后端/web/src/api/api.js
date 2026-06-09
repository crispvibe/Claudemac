import service from '@/utils/request'

export const getApiList = (data) => {
  return service({
    url: '/api-catalog/getApiList',
    method: 'post',
    data
  })
}

export const createApi = (data) => {
  return service({
    url: '/api-catalog/createApi',
    method: 'post',
    data
  })
}

export const getApiById = (data) => {
  return service({
    url: '/api-catalog/getApiById',
    method: 'post',
    data
  })
}

export const updateApi = (data) => {
  return service({
    url: '/api-catalog/updateApi',
    method: 'post',
    data
  })
}

export const setAuthApi = (data) => {
  return service({
    url: '/api-catalog/setAuthApi',
    method: 'post',
    data
  })
}

export const getAllApis = (data) => {
  return service({
    url: '/api-catalog/getAllApis',
    method: 'post',
    data
  })
}

export const deleteApi = (data) => {
  return service({
    url: '/api-catalog/deleteApi',
    method: 'post',
    data
  })
}

export const deleteApisByIds = (data) => {
  return service({
    url: '/api-catalog/deleteApisByIds',
    method: 'delete',
    data
  })
}

export const syncApi = () => {
  return service({
    url: '/api-catalog/syncApi',
    method: 'get'
  })
}

export const getApiGroups = () => {
  return service({
    url: '/api-catalog/getApiGroups',
    method: 'get'
  })
}

export const enterSyncApi = (data) => {
  return service({
    url: '/api-catalog/enterSyncApi',
    method: 'post',
    data
  })
}
