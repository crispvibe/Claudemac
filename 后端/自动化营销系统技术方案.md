# Deep Supply Chain Audit & Boilerplate Purge

执行深度依赖追踪与代码缩减。排除了表面文本特征后，通过追溯 `go.mod` 第三方依赖的 GitHub 源库背景，发现部分看似通用的库实则是原框架作者库的 Fork 版本（带有潜在风险）。

## User Review Required

> [!WARNING]
> **关于 `godoes/gorm-oracle`：**
> 经深入 GitHub 追溯核实，目前引入的 `github.com/godoes/gorm-oracle` 库，其底层代码实际上 Fork 自 `dzwvip/oracle`（dzwvip 即 GVA 核心作者之一）。更严重的是，该 Fork 库在其 GitHub 主页中**明确声明“不建议在生产环境中使用 (not recommended for use in a production environment)”**。
> 使用该库不仅无法彻底消除框架的隐藏技术债，还引入了明确的生产级稳定性风险。

> [!IMPORTANT]
> **数据库驱动精简提议：**
> 由于系统实际已明确只聚焦于 MySQL 运行（高并发场景），GVA 默认自带的冗余多数据库驱动接入层（Oracle、MSSql、PgSql、Sqlite）没有实际业务价值，反而扩大了“供应链攻击面（Supply Chain Attack Surface）”，并留下 GVA 的多库兼容层结构残影。
> 建议直接**物理删除**这些冗余驱动入口及包依赖，仅保留核心的 `gorm_mysql.go` 与通用封装。

## Proposed Changes

根据对 GitHub 第三方组件背景的深度分析与安全性约束，计划进行如下彻底的清理与重构：

### 移除高风险与冗余供应链组件

#### [MODIFY] [go.mod](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/go.mod)
- 移除 `github.com/godoes/gorm-oracle` 及其间接依赖（消除 GVA 原作者 `dzwvip` 生态残余与不安全标识代码）。
- （可选同步处理）移除对 Postgres、Sql Server 专属 Gorm 驱动的引用，让模块依赖树达到最小纯净状态。

#### [DELETE] [gorm_oracle.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/gorm_oracle.go)
- 物理删除带毒的 Oracle 初始化模块。
#### [DELETE] [gorm_mssql.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/gorm_mssql.go)
- 物理删除。
#### [DELETE] [gorm_pgsql.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/gorm_pgsql.go)
- 物理删除。
#### [DELETE] [gorm_sqlite.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/gorm_sqlite.go)
- 物理删除。

### 系统层接口精简同步

#### [MODIFY] [db_list.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/db_list.go)
- 移除对上述四个已删除方言驱动模块的 `switch` 路由判断逻辑。
- 清理 GVA 原生预留的全局多库兼容层“残存死代码”。

#### [MODIFY] [gorm.go](file:///Users/oreo/Desktop/支付系统/禾屿科技/server/initialize/gorm.go)
- 移除多驱动初始化的 `case` 导入逻辑，确保只装载 `mysql` 适配，将数据库接入层完全改造为当前实际的生产单通道架构。

## Open Questions

> [!CAUTION]
> 我已经明确发现了 `godoes/gorm-oracle` 作为 `dzwvip` Fork 版本的隐藏关联及其免责声明。您说的“你想得太简单了”是否指的就是此类通过 Fork “借尸还魂” 的第三方驱动库？
> 如果您同意上述物理删除全部无用数据库驱动、彻底切断此部分供应链依赖的方案，请确认。如果除了这个库，您还发现其他深度的 GitHub 级别库隐患，烦请在此步骤后指出！

## Verification Plan

### 代码验证
- 执行 `go mod tidy` 后，`gorm-oracle` 等将从 `go.sum` 彻底消失。
- 编译生成新文件，系统依赖仅包含 MySQL 与通用组件，后端构建将极为精炼。
