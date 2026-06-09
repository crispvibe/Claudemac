import service from '@/utils/request'

export const getCaptcha = () => {
  return service({
    url: '/auth/captcha',
    method: 'get'
  })
}

export const getSlideCaptcha = () => {
  return service({
    url: '/auth/slide-captcha',
    method: 'get'
  })
}

export const verifySlideCaptcha = (data) => {
  return service({
    url: '/auth/slide-captcha/verify',
    method: 'post',
    data
  })
}

export const login = (data) => {
  return service({
    url: '/auth/login',
    method: 'post',
    data: data
  })
}

export const register = (data) => {
  return service({
    url: '/accounts/create',
    method: 'post',
    data: data
  })
}

export const changePassword = (data) => {
  return service({
    url: '/accounts/password/change',
    method: 'post',
    data: data
  })
}

export const getUserList = (data) => {
  return service({
    url: '/accounts/list',
    method: 'post',
    data: data
  })
}

export const setUserPrimaryRole = (data) => {
  return service({
    url: '/accounts/role/primary',
    method: 'post',
    data: data
  })
}

export const deleteUser = (data) => {
  return service({
    url: '/accounts/remove',
    method: 'delete',
    data: data
  })
}

export const setUserInfo = (data) => {
  return service({
    url: '/accounts/update',
    method: 'put',
    data: data
  })
}

export const setSelfInfo = (data) => {
  return service({
    url: '/accounts/profile',
    method: 'put',
    data: data
  })
}

export const setSelfSetting = (data) => {
  return service({
    url: '/accounts/preferences',
    method: 'put',
    data: data
  })
}

export const setUserRoles = (data) => {
  return service({
    url: '/accounts/roles/update',
    method: 'post',
    data: data
  })
}

export const getUserInfo = (options = {}) => {
  return service({
    url: '/accounts/profile',
    method: 'get',
    // 路由守卫与登录页会将其当做"静默探测会话是否有效"，401 时不应 toast / 不应跳转
    ...options
  })
}

export const resetPassword = (data) => {
  return service({
    url: '/accounts/password/reset',
    method: 'post',
    data: data
  })
}
