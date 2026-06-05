import service from '@/utils/request'
export const jsonInBlacklist = () => {
  return service({
    url: '/auth-tokens/jsonInBlacklist',
    method: 'post'
  })
}
