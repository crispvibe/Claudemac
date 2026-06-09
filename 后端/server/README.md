# 后端服务

支付系统 · 禾屿科技控制台后端（Go Gin + GORM + JWT + Casbin）

## 启动

```bash
# 本地开发
go run . -c config.local.yaml

# 生产
GIN_MODE=release go run . -c config.yaml
```

## 本地首次启动（空库初始化）

1. 本地创建 MySQL 空库并灌入基础表结构：
   ```bash
   mysql -u root -p < server/local-init/bootstrap.sql
   ```
2. 在 `config.local.yaml` 设置 `system.env: local`、`mysql.dbname: pay_anna_vin`。
3. 如需让首启自动注入管理员 / 角色 / 菜单基线，可通过环境变量指定初始密码：
   ```bash
   export HEYU_BOOTSTRAP_PASSWORD='你的强密码'
   go run . -c config.local.yaml
   ```
   服务端只在 `navigation_entries` 为空时注入，幂等；已初始化的库不会被覆写。
4. 默认 `system.disable-auto-migrate: true`：表结构已存在时不做 GORM AutoMigrate。
   若希望首启自动建表，将其改为 `false`，代码会用 `RegisterTables()` 自动同步，同时
   触发基线种子注入逻辑（见 `initialize/local_baseline_seed.go`）。

## 目录结构

| 目录 | 说明 |
| ---- | ---- |
| `api/v1/{admin,biz}` | HTTP 接口层，按业务域拆分 |
| `config/` | `config.yaml` 对应的配置结构体 |
| `core/` | 核心组件初始化：viper、zap、http server |
| `global/` | 进程级全局对象（DB、Redis、Logger、Config） |
| `initialize/` | 启动时装配：gorm、redis、router、timer、validator |
| `middleware/` | Gin 中间件：鉴权、RBAC、限流、日志、CORS、安全头 |
| `model/{admin,biz,common}` | 数据模型（Go struct + GORM 映射） |
| `router/{admin,biz}` | 路由分组装配 |
| `service/{admin,biz}` | 业务逻辑层 |
| `task/` | 定时任务（日志清理等） |
| `utils/` | 工具函数：JWT、验证器、上传、时间、字符串 |

## 约定

- 数据库建表由远端 DBA 管理，服务端默认关闭 `disable-auto-migrate`
- JWT 同时支持 Authorization Bearer 头与 HttpOnly Cookie
- 响应体统一 `{code, data, msg}` 结构
- 登录失败次数限制 + 验证码阈值策略位于 `utils/captcha` 与 `middleware/jwt.go`

## 配置文件

生产配置走 `config.yaml`，本地配置走 `config.local.yaml`，敏感值（JWT 签名、OSS AK/SK、数据库密码）均以占位形式保留，真实值通过环境变量或部署平台下发。
