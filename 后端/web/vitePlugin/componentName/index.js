import fs from 'fs'
import path from 'path'
import chokidar from 'chokidar'

const virtualModuleId = 'virtual:component-registry'
const resolvedVirtualModuleId = `\0${virtualModuleId}`
const manifestRelativePath = '../server/model/admin/component_identifier_manifest.json'
const staleRegistryShadowPath = './src/pathInfo.json'

// 递归获取目录下所有的 .vue 文件
const getAllVueFiles = (dir, fileList = []) => {
  const files = fs.readdirSync(dir)
  files.forEach((file) => {
    const filePath = path.join(dir, file)
    if (fs.statSync(filePath).isDirectory()) {
      getAllVueFiles(filePath, fileList)
    } else if (filePath.endsWith('.vue')) {
      fileList.push(filePath)
    }
  })
  return fileList
}

const toImportPath = (relativePath) => {
  return `/src/${relativePath}`
}

const getManifestFilePath = (root) => {
  return path.resolve(root, manifestRelativePath)
}

const readComponentManifest = (root) => {
  const manifestPath = getManifestFilePath(root)
  return JSON.parse(fs.readFileSync(manifestPath, 'utf-8'))
}

const validateComponentManifest = (entries, viewFiles) => {
  const manifestPaths = new Set(entries.map((entry) => entry.relativePath))
  const viewPathSet = new Set(viewFiles)
  const missingManifestEntries = viewFiles.filter((relativePath) => !manifestPaths.has(relativePath))
  const redundantManifestEntries = entries
    .map((entry) => entry.relativePath)
    .filter((relativePath) => !viewPathSet.has(relativePath))

  if (missingManifestEntries.length > 0 || redundantManifestEntries.length > 0) {
    throw new Error(
      `component identifier manifest mismatch: missing=${missingManifestEntries.join(',')} redundant=${redundantManifestEntries.join(',')}`
    )
  }
}

const createRegistryWrapperSource = () => {
  return `export { componentRegistry, namedComponentIds } from '${virtualModuleId}'\n`
}

const buildRegistrySource = (entries, namedComponentIds) => {
  const componentRegistryEntries = entries
    .map((entry) => {
      return `  ${JSON.stringify(entry.componentId)}: {
    loader: () => import(${JSON.stringify(entry.importPath)})
  }`
    })
    .join(',\n')

  const namedComponentIdEntries = Object.entries(namedComponentIds)
    .map(([key, componentId]) => {
      return `  ${JSON.stringify(key)}: ${JSON.stringify(componentId)}`
    })
    .join(',\n')

  return `export const componentRegistry = {\n${componentRegistryEntries}\n}\n\nexport const namedComponentIds = {\n${namedComponentIdEntries}\n}\n`
}

// Vite 插件定义
const vueFilePathPlugin = (outputFilePath) => {
  let root
  let devServer
  let registryModuleSource = ''

  const generateComponentRegistry = () => {
    const viewFiles = getAllVueFiles(path.join(root, 'src/view'))
      .map((filePath) => path.relative(path.join(root, 'src'), filePath).replace(/\\/g, '/'))
      .sort()
    const manifest = readComponentManifest(root)
    validateComponentManifest(manifest.entries || [], viewFiles)
    const entries = (manifest.entries || []).map((entry) => ({
      relativePath: entry.relativePath,
      importPath: toImportPath(entry.relativePath),
      componentId: entry.componentId
    }))
    registryModuleSource = buildRegistrySource(entries, manifest.namedComponentIds || {})
    fs.writeFileSync(path.resolve(root, outputFilePath), createRegistryWrapperSource())
    fs.writeFileSync(path.resolve(root, staleRegistryShadowPath), '{}\n')
  }

  const watchDirectoryChanges = () => {
    const watchDirectories = [path.join(root, 'src/view')]
    const watcher = chokidar.watch(watchDirectories, {
      persistent: true,
      ignoreInitial: true
    })
    watcher.on('all', () => {
      generateComponentRegistry()
      if (devServer) {
        devServer.ws.send({ type: 'full-reload' })
      }
    })
  }

  return {
    name: 'vue-file-path-plugin',
    resolveId(id) {
      if (id === virtualModuleId) {
        return resolvedVirtualModuleId
      }
      return null
    },
    load(id) {
      if (id === resolvedVirtualModuleId) {
        return registryModuleSource
      }
      return null
    },
    configResolved(resolvedConfig) {
      root = resolvedConfig.root
    },
    configureServer(server) {
      devServer = server
    },
    buildStart() {
      generateComponentRegistry()
    },
    buildEnd() {
      if (process.env.NODE_ENV === 'development') {
        watchDirectoryChanges()
      }
    }
  }
}

export default vueFilePathPlugin
