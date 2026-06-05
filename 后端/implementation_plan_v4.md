# 指纹深度清零方案 v4

> 目标：让代码仓 **无法通过结构、命名、骨架、模板与 GVA / gin-vue-admin 做结构相似度比对**。  
> 原则：每步都要保证**编译通过 + 功能连通**，任何一处新断链必须立刻修复，不留半成品。  
> 落地方式：生成方案后**按顺序直接改**，中间不再征询，最后做一次完整回归与动态验证。

---

## 一、扫描到的剩余指纹全景

| # | 位置 | 类型 | 证据 | 处理 |
|---|---|---|---|---|
| F1 | `server/utils/plugin/` + `server/utils/plugin/v2/` | GVA 插件接口骨架 | 代码无消费方 (`plugin.Register`, `plugin.Registered` grep 零命中) | **整体删除** |
| F2 | `server/resource/plugin/**/*.tpl` + `server/resource/function/*.tpl` + `server/resource/mcp/*.tpl` | GVA AutoCode 插件模板 | 26 个 tpl 文件，无 Go 引用 | **整体删除** |
| F3 | `server/{api/v1,service,router,model}/system/` 目录名 | Go 包目录仍叫 `system` | 30 个 `.go` 声明 `package system` | **重命名** 为 `server/{api/v1,service,router,model}/admin/`（或其他业务化名字） |
| F4 | `web/src/api/system/` | 空目录孤儿 | `ls` 为空 | **直接删除** |
| F5 | `web/src/view/console/` 目录命名 | 非品牌指纹但仍留 GVA 痕迹 | 约 10 个 `.vue` 位于此 | 保留（业务语义），只清子目录残留 |
| F6 | `server/service/system/operation_record.go:10,19,29,39,49` 注释 | `CreateSysOperationRecord` 等 5 行 godoc | grep 命中 | 注释内容去 Sys 化 |
| F7 | `web/dist/` 旧构建产物中含 `sysOperationRecord` 字节 | 产物 | `dist/assets/*-legacy.js` grep 命中 | 重新 `npm run build` 覆盖 |
| F8 | `server/router/system/{login_log,menu,api,casbin,role,user,base,jwt,operation_record}.go` 等 | 目录名指纹 | 连锁 F3 | 随 F3 统一重命名 |
| F9 | 前端 `view/system/` 目录 | 已删除（上一轮） | `find` 零命中 | 无需动 |
| F10 | `view/console/api/` `view/console/roles/` `view/console/navigation/` 等 | 业务目录，非指纹 | — | 保留 |

---

## 二、改动顺序（一刀一刀切，每刀跑编译）

### 步骤 1：删插件骨架 F1 + F2
1. `rm -rf server/utils/plugin server/utils/plugin/v2`
2. `rm -rf server/resource/plugin server/resource/function server/resource/mcp`
3. `rmdir server/resource` 如为空
4. `cd server && go test ./...` 确认零引用、编译通过

### 步骤 2：清前端空目录 F4
1. `rmdir web/src/api/system`
2. 运行 `npm run build` 确认不受影响

### 步骤 3：Go 包 `system` -> `admin` 大重命名 F3 + F8
> 这是整改最大的一刀。Go 里改 `package` 名 + 目录名，需同步所有 `import` 路径与 `package` 声明。  
> 为避免编译间断，按以下子步执行：

1. **内部扫描**：统计当前 `package system` 声明数与 `import "heyu/server/*/system*` 引用数。
2. **同步重命名**（脚本一把梭）：
   - `git mv` 四个目录：
     - `server/model/system` -> `server/model/admin`
     - `server/api/v1/system` -> `server/api/v1/admin`
     - `server/service/system` -> `server/service/admin`
     - `server/router/system` -> `server/router/admin`
   - 子包同步：`server/model/system/request` / `response` 跟着走
3. **批量替换**：
   - Go 源码中的 `package system` -> `package admin`（仅限上述目录下）
   - `"heyu/server/model/system"` -> `"heyu/server/model/admin"`
   - `"heyu/server/api/v1/system"` -> `"heyu/server/api/v1/admin"`
   - `"heyu/server/service/system"` -> `"heyu/server/service/admin"`
   - `"heyu/server/router/system"` -> `"heyu/server/router/admin"`
   - `"heyu/server/model/system/request"` -> `"heyu/server/model/admin/request"`
   - `"heyu/server/model/system/response"` -> `"heyu/server/model/admin/response"`
   - 别名 `systemReq` / `systemRes` 可保留（它们是 import 别名，不是指纹）
4. **聚合骨架同步**：
   - `server/api/v1/enter.go` `APIPack.System` -> `APIPack.Admin`
   - `server/service/enter.go` `ServicePack.System` -> `ServicePack.Admin`
   - `server/router/enter.go` `RouterPack.System` -> `RouterPack.Admin`
   - 所有 `api.APIs.System.XxxApi` -> `api.APIs.Admin.XxxApi`
   - 所有 `service.Services.System.XxxService` -> `service.Services.Admin.XxxService`
   - 所有 `router.Routers.System` -> `router.Routers.Admin`
5. **`go test ./...` 通过**
6. **前端 build 通过**
7. **后端起服务 + 核心接口 smoke test**

### 步骤 4：清注释 F6
- `operation_record.go` 里的 5 行 `@function: CreateSysOperationRecord` 等 godoc 改为业务化表述。

### 步骤 5：清前端旧构建产物 F7
- `rm -rf web/dist`
- `npm run build` 生成无指纹产物

### 步骤 6：全量回归
1. `go test ./...`
2. `npm run build`
3. 后端启动 + 登录 + 7 条核心接口动态验证：
   - `POST /auth/login`
   - `GET /accounts/profile`
   - `POST /navigation/routes`
   - `GET /operation-logs/list`
   - `GET /security/captcha-config`
   - `GET /dashboard/panel`
   - 旧路径（预期 404）：`/system/captcha-config`

---

## 三、风险与兜底

| 风险 | 可能触发 | 兜底 |
|---|---|---|
| Go 目录重命名后 import 漏改 | 编译失败 | 每一子步跑 `go build` 立即暴露 |
| 子包 request/response 丢失 | 引用断链 | 一次 `git mv` 整目录，import 自动对齐 |
| 前端 componentRegistry 校验失败 | build error | 没有前端文件重命名，本轮不改 vue 文件，manifest 与磁盘一致 |
| 后门路由引入 | 新暴露 | 本轮**只删不加**，不新增任何路由 |

---

## 四、完成定义（Definition of Done）

1. `find server -type d -name 'system'` 零命中
2. `find server/resource -type f -name '*.tpl'` 零命中
3. `find server/utils -type d -name 'plugin'` 零命中
4. `grep -rnE '^package system$' server/` 零命中
5. `grep -rnE '"heyu/server/[^"]*/system' server/` 零命中
6. `find web/src/api -type d -empty` 零命中
7. `find web/dist -name '*sysOperationRecord*'` 零命中
8. `go test ./...` 通过
9. `npm run build` 通过
10. 7 条接口动态验证通过
