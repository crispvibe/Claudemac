import service from '@/utils/request'

export const getDashboardPanel = () => {
  return service({
    url: '/dashboard/panel',
    method: 'get'
  })
}
