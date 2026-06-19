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

export const getEmailConfig = () => {
  return service({
    url: '/security/email-config',
    method: 'get'
  })
}

export const updateEmailConfig = (data) => {
  return service({
    url: '/security/email-config',
    method: 'put',
    data
  })
}

export const sendTestEmail = (data) => {
  return service({
    url: '/security/email-config/test',
    method: 'post',
    data
  })
}
