import { createRouter, createWebHashHistory } from 'vue-router'

// __ADMIN_SLUG__ 由 vite.config.js 的 define 在构建期注入；形如 "/a1b2c3d4e5f6a7b8" 或 ""
// 登录页只暴露在 /${slug}/login，未带 slug 的访问统一落到 404，避免前端入口被扫出
const adminSlugRaw = (typeof __ADMIN_SLUG__ !== 'undefined' && __ADMIN_SLUG__) || ''
const adminSlug = adminSlugRaw.replace(/\/+$/, '')

export const adminLoginPath = adminSlug ? `${adminSlug}/login` : '/login'
// 登录后主 layout 容器也挂在 slug 下，保证登录前/登录后地址栏形式一致
// 例如 slug = "/592c904e316e3dd1" 时，业务页会是 /#/592c904e316e3dd1/layout/dashboard
export const adminLayoutPath = adminSlug ? `${adminSlug}/layout` : '/layout'
// 纯 slug 前缀，供顶级路由（defaultMenu / 基础页面）拼接绝对路径使用
// 例如 slug = "/592c904e316e3dd1" 时，defaultMenu 基础页路径会是 /#/592c904e316e3dd1/dashboard
export const adminBasePath = adminSlug

const routes = [
  {
    path: adminLoginPath,
    name: 'Login',
    component: () => import('@/view/login/index.vue')
  },
  {
    path: '/:catchAll(.*)',
    name: 'NotFound',
    meta: {
      closeTab: true,
      client: true
    },
    component: () => import('@/view/error/index.vue')
  }
]

const router = createRouter({
  history: createWebHashHistory(),
  routes
})

export default router

