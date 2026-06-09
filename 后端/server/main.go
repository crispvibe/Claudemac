package main

import (
	"heyu/server/bootstrap"
	"heyu/server/global"
	"heyu/server/initialize"
	_ "go.uber.org/automaxprocs"
	"go.uber.org/zap"
)

//go:generate go env -w GO111MODULE=on
//go:generate go mod tidy
//go:generate go mod download

// 这部分 @Tag 设置用于排序, 需要排序的接口请按照下面的格式添加
// swag init 对 @Tag 只会从入口文件解析, 默认 main.go
// 也可通过 --generalInfo flag 指定其他文件
// @Tag.Name        Base
// @Tag.Name        Account
// @Tag.Description 用户

// @title                       禾屿科技接口文档
// @version                     v2.8.9
// @description                 禾屿科技后端接口文档
// @securityDefinitions.apikey  ApiKeyAuth
// @in                          header
// @name                        Authorization
// @BasePath                    /
func main() {
	// 初始化系统
	initializeSystem()
	// 运行服务器
	bootstrap.RunServer()
}

// initializeSystem 初始化系统所有组件
// 提取为单独函数以便于系统重载时调用
func initializeSystem() {
	global.AppVP = bootstrap.Viper() // 初始化Viper
	initialize.OtherInit()
	global.AppLog = bootstrap.Zap() // 初始化zap日志库
	zap.ReplaceGlobals(global.AppLog)
	initialize.EnsureAdminSlug() // 保证后台入口 slug 已生成且规范化
	global.AppDB = initialize.Gorm() // gorm连接数据库
	initialize.Timer()
	initialize.DBList()
	initialize.SetupHandlers() // 注册全局函数
	if global.AppDB != nil {
		if err := initialize.RegisterJoinTables(); err != nil {
			global.AppLog.Fatal("register join tables failed", zap.Error(err))
		}
		initialize.RegisterTables() // 初始化表
		if err := initialize.NormalizeMenuComponentIdentifiers(); err != nil {
			global.AppLog.Fatal("normalize menu component identifiers failed", zap.Error(err))
		}
	}
}
