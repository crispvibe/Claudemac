import service from '@/utils/request'

export const listNotifications = (data) => {
  return service({
    url: '/notifications/list',
    method: 'post',
    data
  })
}

export const getUnreadCount = () => {
  return service({
    url: '/notifications/unread-count',
    method: 'get'
  })
}

export const getNotificationDetail = (id) => {
  return service({
    url: '/notifications/detail',
    method: 'post',
    data: { id }
  })
}

export const markNotificationRead = (id) => {
  return service({
    url: '/notifications/read',
    method: 'post',
    data: { id }
  })
}

export const markAllNotificationsRead = () => {
  return service({
    url: '/notifications/read-all',
    method: 'post'
  })
}
