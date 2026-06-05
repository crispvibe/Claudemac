# 系统冗余清理方案 v6 — 完美化收尾

> 目标：清除经过 v3–v5 指纹清理后遗留的**冷代码、空文件、未用依赖、废弃接口登记**，让系统达到"完美"。
>
> **不动业务逻辑**，只做冗余删除 + 名录归正。

---

## 一、全景扫描结果

### A 区：数据库接口名录（25 条强冗余）

`api_catalog` 表 87 条 vs 运行路由 62 条 = **25 条全是历史指纹残留**。由后端 `/api-catalog/syncApi` 给出权威 deleteApis 列表：

| 分组 | 冗余路径 | id |
|---|---|---|
| 旧 `/authority/*` → 已改为 `/roles/*` | 6 条（copyAuthority / createAuthority / deleteAuthority / getAuthorityList / setDataAuthority / updateAuthority） | 23-28 |
| 旧 `/menu/*` → 已改为 `/navigation/*` | 9 条（addBaseMenu / addMenuAuthority / deleteBaseMenu / getBaseMenuById / getBaseMenuTree / getMenu / getMenuAuthority / getMenuList / updateBaseMenu） | 31-39 |
| 旧 `/operation-logs/*Sys*` → 已改为 `/operation-logs/{list,detail,delete,deleteByIds}` | 4 条 | 41-44 |
| 旧 `/sysOperationRecord/createSysOperationRecord` | 1 条 | 40 |
| 旧 `/system/captcha-config` → 已改为 `/security/captcha-config` | 2 条（GET/PUT） | 80, 81 |
| 旧 `/base/login` → 已改为 `/auth/login` | 1 条 | 59 |
| 旧 `/user/admin_register` / `/user/getUserList` | 2 条 | 3, 4 |
| **合计** | | **25 条** |

### B 区：后端 Go 冗余

| 文件 / 代码 | 冗余原因 | 处理 |
|---|---|---|
| `@/Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/register_init.go` | 空文件（只剩 `package initialize`） | 删除 |
| `@/Users/oreo/Desktop/支付系统/禾屿科技/server/model/admin/request/version.go` | 空文件 | 删除 |
| `@/Users/oreo/Desktop/支付系统/禾屿科技/server/model/admin/response/version.go` | 空文件 | 删除 |
| `@/Users/oreo/Desktop/支付系统/禾屿科技/server/model/admin/role_menu.go:21` 末尾孤儿注释 | 注释说"兼容别名"但没任何代码 | 删除注释行 |

### C 区：前端冷文件

**未被任何地方引用的 API 文件（2 个）**：
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/api/email.js` — 0 引用
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/api/loginLog.js` — 0 引用（loginLog 页面已走 `@/api/user`）

**未被引用的工具函数（5 个）**：
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/utils/btnAuth.js` — 0 引用
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/utils/closeThisPage.js` — 0 引用
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/utils/doc.js` — 0 引用
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/utils/downloadImg.js` — 0 引用
- `@/Users/oreo/Desktop/支付系统/禾屿科技/web/src/utils/env.js` — 0 引用

### D 区：前端 npm 冷依赖（19 个，共 ~8-15MB）

| 包 | 场景 | 处理 |
|---|---|---|
| `@form-create/designer` + `@form-create/element-ui` + `vform3-builds` | 表单设计器（未使用） | 删 |
| `@wangeditor/editor` | 富文本编辑器（未使用） | 删 |
| `@vueuse/integrations` | vueuse 集成（未使用） | 删 |
| `ace-builds` + `vue3-ace-editor` | 代码编辑器（未使用） | 删 |
| `@unocss/transformer-directives` | unocss 指令转换（uno.css 已生效但未用这个） | 删 |
| `core-js` | polyfill（Vite + ES2020+ target 无需） | 删 |
| `highlight.js` + `marked` + `marked-highlight` | Markdown 渲染（未使用） | 删 |
| `qs` | querystring 库（axios 自带） | 删 |
| `sortablejs` + `vuedraggable` | 拖拽排序（未使用） | 删（vuedraggable 也 0 引用） |
| `spark-md5` | 文件 hash（未使用） | 删 |
| `universal-cookie` | cookie 库（未使用） | 删 |
| `vue-echarts` | 图表（当前仪表盘用 echarts 直接） | 需人工确认（见下） |
| `vue3-sfc-loader` | 运行时加载 .vue（未使用） | 删 |

**待确认（1 次引用）**：`@iconify/vue` / `vue-cropper` / `vue-qr` — 这些是 1 次引用，保留。

### E 区：后端 / 前端 — 保留项（说明）

以下看起来冷但**故意保留**（支持未来切换），不在清理范围：
- 后端 GORM 的 `GormPgSql / GormOracle / GormMssql / GormSqlite` + 对应 config 块
- 后端 OSS 8 种 provider（local/qiniu/tencent/aliyun/huawei/aws/cloudflare/minio）+ 对应 config 块
- 后端 Mongo（`config.use-mongo: false` 时不连，但结构保留）
- 后端 `menu_component_migration.go`（每次启动做一次性的幂等迁移，非冗余）
- 前端 `@iconify/vue`/`@vue-office/*` 系列（在 `view/*` 内引用，保留）

---

## 二、执行步骤

1. **A 区** — 用 `/api-catalog/enterSyncApi` 后端自带的同步接口，一次性删除 25 条冗余记录
2. **B 区** — 删除 3 个空 `.go` 文件 + `role_menu.go:21` 悬空注释
3. **C 区** — 删除 7 个前端冷文件
4. **D 区** — `npm uninstall` 19 个冷依赖
5. **验证** — `go build ./...` + `npm run build` + 接口回归 5 条 + 登录滑块完整链路
6. **事后** — `/api-catalog/syncApi` 再跑一次应返回 `deleteApis: []  newApis: []`

---

## 三、完成定义 DoD

| 验证点 | 期望 |
|---|---|
| `SELECT COUNT(*) FROM api_catalog` | 62 |
| `/api-catalog/syncApi` 返回 deleteApis | `[]` |
| `/api-catalog/syncApi` 返回 newApis | `[]` |
| `find server -name '*.go' -size -50c` | 0 |
| 前端 7 个冷文件 | 不存在 |
| `npm ls --depth=0` 无冷依赖 | 19 个全消失 |
| `go build ./...` | 通过 |
| `npm run build` | 通过 |
| 后端动态验证：登录 + 5 核心接口 + 滑块链路 | 全 200 |

---

## 四、回滚策略

- A 区冗余接口删除前，SQL 先 `EXPORT` 存备份到 `/tmp/api_catalog_removed.sql`
- B/C 区文件删除前 git 已追踪，`git restore` 可恢复
- D 区 `npm uninstall` 失败可 `npm install <pkg>` 回装

---

## 五、风险评估

| 风险 | 评级 | 缓解 |
|---|---|---|
| 删 `@form-create/designer` 影响在线表单设计器 | 低 | 当前项目**无**表单设计器页面，grep 已确认 |
| 删 `core-js` 影响老浏览器兼容 | 低 | Vite + ESBuild target=es2020，覆盖主流浏览器 |
| 删 `qs` 影响 axios | 无 | axios 1.7+ 自带 query 序列化 |
| 删 DB 旧接口导致前端找不到 | 无 | 前端已全部迁移到新路径 |

---

**生成完毕，请确认是否执行。可选范围：**
- 全选：A+B+C+D 一把清理
- 只清 A+B：只动接口名录和空 Go 文件，不碰前端依赖
- 只清 A：最小改动，只做数据库 sync
