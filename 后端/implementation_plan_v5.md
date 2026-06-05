# 指纹深度清零方案 v5 — 法医级审计

> 目标：挖出 v4 之后仍存在的、**非常隐蔽、非常细小、非常深层**的 GVA 残骸。
> 按"**证据 → 清理 → 编译 → 动态验证**"序贯执行。

## 一、本轮扫描到的漏网之鱼（按隐蔽度排序）

| # | 位置 | 问题 | 证据 | 处理 |
|---|---|---|---|---|
| **L1** | `server/local-init` | 仓库里有一个 49MB Mach-O arm64 二进制 | `file` 命令确认 | 删除 + `.gitignore` 忽略 |
| **L2** | `server/log/` | 每日日志 + `compatibility-migration.state` 状态文件污染仓库 | `ls` 命中 | 清空日志目录，`.gitignore` 已忽略 |
| **L3** | `scripts/local-init.sh` | 引用不存在的 `./cmd/local-init` | 路径失效，cmd 目录不存在 | 删除失效脚本，或改成调用仓库里实际存在的启动方式 |
| **L4** | `server/README.md` | **53 行 GVA 原版目录结构描述**，含 `packfile`、`resource/excel`、`resource/page`、`resource/template`、`source`、`docs` 等 GVA 特征目录名 | 文件内容 | 重写为当前项目真实结构 |
| **L5** | `implementation_plan.md` + `v2` + `v3` 根级 | 历史方案文件，提示性强，泄露重构历史 | `ls` 命中 4 个 | 留 v5 一份即可；其他归档或删除 |
| **L6** | `server/service/admin/schema_migration.go` | 空文件，只剩 `package admin` 一行 | `head` 输出 | 删除 |
| **L7** | `server/service/admin/compatibility_migration.go` | 同上，空文件 | `head` 输出 | 删除 |
| **L8** | `web/src/api/initdb.js` | `export {}` 空壳，无消费方 | grep 零消费 | 删除 |
| **L9** | `web/src/pathInfo.json` | `{}` 空文件，vitePlugin 残留占位（旧 GVA autocode 特征） | 内容 `{}` | 删除（vitePlugin 会在 buildStart 重写，但内容是空，也可不保留） |
| **L10** | `server/middleware/cors.go` | CORS 头含非标准 `AccessToken` 字段 | grep 命中 | 移除 `AccessToken`，保留 `Authorization` 即可 |
| **L11** | `server/global/global.go` | 变量 `AppDB/AppLog/AppConfig/AppRedis` 前缀 `App` 是 GVA 风，`AppDBList` / `AppActiveDBName` 未使用 | 无真正引用 | 本轮不改命名（改动面巨大且非强指纹），但清理未使用变量 |
| **L12** | `server/config.yaml` | 大量占位配置 `your-*` / `xxx` | grep 命中 10 余处 | 已是占位值，保留不动（生产环境用 env 覆盖） |

## 二、执行顺序

1. 删除 `server/local-init` 二进制，`.gitignore` 加规则
2. 清空 `server/log/`
3. 删除 `scripts/local-init.sh`（该功能已由 `go run . -c config.local.yaml` 直接启动取代）
4. 重写 `server/README.md` 反映真实结构
5. 删除 `implementation_plan.md` / `implementation_plan_v2.md` / `implementation_plan_v3.md`（保留 v4/v5 作为最近两轮历史）
6. 删除 `server/service/admin/schema_migration.go` / `compatibility_migration.go` 空文件
7. 删除 `web/src/api/initdb.js` + `web/src/pathInfo.json`
8. `server/middleware/cors.go` 移除 `AccessToken` 头
9. `go test ./...` + `npm run build`
10. 启后端动态验证 7 条核心接口 + 旧路径 404

## 三、完成定义
- `file server/local-init` 零输出
- `find server/log -type f` 零输出
- `find server -name schema_migration.go -o -name compatibility_migration.go` 零命中
- `find web/src -name initdb.js -o -name pathInfo.json` 零命中
- `grep 'AccessToken' server/middleware/cors.go` 零命中
- `head server/README.md` 不再含 `packfile/resource/excel/resource/page/source`
- `go test ./...` 通过
- `npm run build` 通过
- 动态验证通过
