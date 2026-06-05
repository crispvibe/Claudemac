import { fmtTitle } from '@/utils/route-title'
import config from '@/core/config'
export default function getPageTitle(pageTitle, route) {
  if (pageTitle) {
    const title = fmtTitle(pageTitle, route)
    return `${title} - ${config.appName}`
  }
  return `${config.appName}`
}
