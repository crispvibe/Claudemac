import service from '@/utils/request'

export const getCaptchaConfig = () => {
  return service({
    url: '/security/captcha-config',
    method: 'get'
  })
}

export const updateCaptchaConfig = (data) => {
  return service({
    url: '/security/captcha-config',
    method: 'put',
    data
  })
}
