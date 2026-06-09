import config from './config'
import { h } from 'vue'

// 统一导入el-icon图标
import * as ElIconModules from '@element-plus/icons-vue'
import svgIcon from '@/components/svgIcon/svgIcon.vue'
// 导入转换图标名称的函数

const createIconComponent = (name) => ({
  name: 'SvgIcon',
  render() {
    return h(svgIcon, {
      localIcon: name
    })
  }
})

const registerIcons = async (app) => {
  const iconModules = import.meta.glob('@/assets/icons/**/*.svg') // 系统目录 svg 图标
  let allKeys = []
  for (const path in iconModules) {
    const iconName = path
      .split('/')
      .pop()
      .replace(/\.svg$/, '')
    // 如果iconName带空格则不加入到图标库中并且提示名称不合法
    if (iconName.indexOf(' ') !== -1) {
      console.error(`icon ${iconName}.svg includes whitespace in ${path}`)
      continue
    }
    const key = iconName
    const iconComponent = createIconComponent(key)
    config.logs.push({
      key: key,
      label: key
    })
    app.component(key, iconComponent)

    // 开发模式下列出所有 svg 图标，方便开发者直接查找复制使用
    allKeys.push(key)
  }

  import.meta.env.MODE == 'development' &&
    console.log(`所有可用的本地图标: ${allKeys.join(', ')}`)
}

export const register = (app) => {
  // 统一注册el-icon图标
  for (const iconName in ElIconModules) {
    app.component(iconName, ElIconModules[iconName])
  }
  app.component('SvgIcon', svgIcon)
  registerIcons(app)
  app.config.globalProperties.$APP_CONFIG = config
}
