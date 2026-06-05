import legacyPlugin from '@vitejs/plugin-legacy'
import * as path from 'path'
import * as dotenv from 'dotenv'
import * as fs from 'fs'
import { randomBytes } from 'node:crypto'
import vuePlugin from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'
import VueFilePathPlugin from './vitePlugin/componentName/index.js'
import UnoCSS from '@unocss/vite'

// 读取后端已生成的随机后台 slug（system.router-prefix），用于 dev 代理 rewrite。
// 优先级：VITE_ADMIN_SLUG 环境变量 > server/config.local.yaml > server/config.yaml > 空串
const readAdminSlugFromYaml = (yamlPath) => {
  try {
    const content = fs.readFileSync(yamlPath, 'utf-8')
    const match = content.match(/^\s{4}router-prefix:\s*(.+)$/m)
    if (!match) return ''
    let value = match[1].trim()
    value = value.replace(/^["']|["']$/g, '')
    if (!value) return ''
    if (!value.startsWith('/')) value = '/' + value
    return value.replace(/\/+$/, '')
  } catch (e) {
    return ''
  }
}

const resolveAdminSlug = () => {
  const fromEnv = process.env.VITE_ADMIN_SLUG
  if (fromEnv) {
    const normalized = fromEnv.startsWith('/') ? fromEnv : '/' + fromEnv
    return normalized.replace(/\/+$/, '')
  }
  const candidates = [
    path.resolve(__dirname, '../server/config.local.yaml'),
    path.resolve(__dirname, '../server/config.yaml')
  ]
  for (const candidate of candidates) {
    const slug = readAdminSlugFromYaml(candidate)
    if (slug) return slug
  }
  return ''
}

// Vite 构建配置
export default ({ mode }) => {
  const NODE_ENV = mode || 'development'
  const envFiles = [`.env.${NODE_ENV}`]
  for (const file of envFiles) {
    const envConfig = dotenv.parse(fs.readFileSync(file))
    for (const k in envConfig) {
      process.env[k] = envConfig[k]
    }
  }

  const adminSlug = resolveAdminSlug()
  if (adminSlug) {
    console.log(`[vite] dev 代理已绑定后台入口 slug: ${adminSlug}`)
  } else {
    console.log('[vite] 未检测到后台入口 slug，将直接透传 /api/* 到后端根路径。首次启动后端后会在 server/config.local.yaml 写入 system.router-prefix，重启 vite 即可生效。')
  }

  const assetBucket = randomBytes(6).toString('hex')

  const createRandomAssetFileName = (extension) => {
    return `assets/${assetBucket}/${randomBytes(10).toString('hex')}.${extension}`
  }

  const resolveAssetExtension = (fileName = '') => {
    const extension = path.extname(fileName).replace('.', '')
    return extension || 'bin'
  }

  const resolveManualChunk = (id) => {
    if (!id.includes('node_modules')) {
      return undefined
    }

    const normalizedId = id.replace(/\\/g, '/')

    if (normalizedId.includes('@wangeditor')) {
      return 'vendor-editor'
    }

    if (normalizedId.includes('@vue-office/docx')) {
      return 'vendor-office-docx'
    }

    if (normalizedId.includes('@vue-office/excel')) {
      return 'vendor-office-excel'
    }

    if (normalizedId.includes('@vue-office/pdf')) {
      return 'vendor-office-pdf'
    }

    if (normalizedId.includes('@vue-office')) {
      return 'vendor-office'
    }

    if (normalizedId.includes('echarts') || normalizedId.includes('zrender') || normalizedId.includes('vue-echarts')) {
      return 'vendor-charts'
    }

    if (normalizedId.includes('element-plus')) {
      return 'vendor-element'
    }

    if (normalizedId.includes('@element-plus/icons-vue')) {
      return 'vendor-element-icons'
    }

    if (normalizedId.includes('@iconify')) {
      return 'vendor-iconify'
    }

    if (normalizedId.includes('vuedraggable')) {
      return 'vendor-dnd'
    }

    if (normalizedId.includes('vue-cropper') || normalizedId.includes('vue-qr')) {
      return 'vendor-media'
    }

    if (normalizedId.includes('go-captcha-vue')) {
      return 'vendor-security'
    }

    if (
      normalizedId.includes('/vue/') ||
      normalizedId.includes('/@vue/') ||
      normalizedId.includes('/vue-router/') ||
      normalizedId.includes('/pinia/') ||
      normalizedId.includes('/@vueuse/core/') ||
      normalizedId.includes('/mitt/') ||
      normalizedId.includes('/nprogress/') ||
      normalizedId.includes('/screenfull/')
    ) {
      return 'vendor-framework'
    }

    return undefined
  }

  const optimizeDeps = {}

  const alias = {
    '@': path.resolve(__dirname, './src'),
    vue$: 'vue/dist/vue.runtime.esm-bundler.js'
  }

  const esbuild = {}

  const rollupOptions = {
    output: {
      entryFileNames: () => createRandomAssetFileName('js'),
      chunkFileNames: () => createRandomAssetFileName('js'),
      assetFileNames: (assetInfo) => createRandomAssetFileName(resolveAssetExtension(assetInfo?.name)),
      manualChunks: resolveManualChunk
    }
  }

  const base = "/"
  const root = "./"
  const outDir = "dist"

  const config = {
    base: base, // 编译后js导入的资源路径
    root: root, // index.html文件所在位置
    publicDir: 'public', // 静态资源文件夹
    resolve: {
      alias
    },
    define: {
      'process.env': {},
      // 把后台 slug 作为构建期常量注入前端，登录页路由会拼成 /${slug}/login
      __ADMIN_SLUG__: JSON.stringify(adminSlug || '')
    },
    css: {
      preprocessorOptions: {
        scss: {
          api: 'modern-compiler' // or "modern"
        }
      }
    },
    server: {
      // 如果使用docker-compose开发模式，设置为false
      open: true,
      port: process.env.VITE_CLI_PORT,
      proxy: {
        // 前端所有 /api/* 请求，开发时被改写成 `${adminSlug}/*` 转发到后端
        [process.env.VITE_BASE_API]: {
          target: `${process.env.VITE_BASE_PATH}:${process.env.VITE_SERVER_PORT}/`,
          changeOrigin: true,
          rewrite: (reqPath) => {
            const apiPrefixRegex = new RegExp('^' + process.env.VITE_BASE_API)
            const stripped = reqPath.replace(apiPrefixRegex, '')
            return adminSlug + stripped
          }
        }
      }
    },
    build: {
      minify: 'terser', // 是否进行压缩,boolean | 'terser' | 'esbuild',默认使用terser
      manifest: false, // 是否产出manifest.json
      sourcemap: false, // 是否产出sourcemap.json
      outDir: outDir, // 产出目录
      terserOptions: {
        compress: {
          //生产环境时移除console
          drop_console: true,
          drop_debugger: true
        }
      },
      rollupOptions
    },
    esbuild,
    optimizeDeps,
    plugins: [
      // process.env.VITE_POSITION === 'open' &&
      // vueDevTools({ launchEditor: process.env.VITE_EDITOR }),
      legacyPlugin({
        targets: [
          'Android > 39',
          'Chrome >= 60',
          'Safari >= 10.1',
          'iOS >= 10.3',
          'Firefox >= 54',
          'Edge >= 15'
        ]
      }),
      vuePlugin(),
      VueFilePathPlugin('./src/componentRegistry.generated.js'),
      UnoCSS()
    ]
  }
  return config
}
