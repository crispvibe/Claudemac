import './style/element_visiable.scss'
import 'element-plus/theme-chalk/dark/css-vars.css'
import 'uno.css'
import { createApp } from 'vue'
import ElementPlus from 'element-plus'

import 'element-plus/dist/index.css'
import GoCaptchaVue from 'go-captcha-vue'
// 引入封装的router
import router from '@/router/index'
import '@/permission'
import run from '@/core/app-init.js'
import auth from '@/directive/auth'
import clickOutSide from '@/directive/click-outside'
import { store } from '@/pinia'
import App from './App.vue'

const app = createApp(App)

app.config.productionTip = false

app
  .use(run)
  .use(ElementPlus)
  .use(GoCaptchaVue)
  .use(store)
  .use(auth)
  .use(clickOutSide)
  .use(router)
  .mount('#app')
export default app
