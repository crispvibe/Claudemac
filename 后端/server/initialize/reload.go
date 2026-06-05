package initialize

import (
	"heyu/server/global"
	"go.uber.org/zap"
)

// Reload 优雅地重新加载系统配置
func Reload() error {
	global.AppLog.Info("正在重新加载系统配置...")

	// 重新加载配置文件
	if err := global.AppVP.ReadInConfig(); err != nil {
		global.AppLog.Error("重新读取配置文件失败!", zap.Error(err))
		return err
	}

	// 重新初始化数据库连接
	if global.AppDB != nil {
		db, _ := global.AppDB.DB()
		err := db.Close()
		if err != nil {
			global.AppLog.Error("关闭原数据库连接失败!", zap.Error(err))
			return err
		}
	}

	// 重新建立数据库连接
	global.AppDB = Gorm()

	// 重新初始化其他配置
	OtherInit()
	DBList()

	if global.AppDB != nil {
		if err := RegisterJoinTables(); err != nil {
			global.AppLog.Error("注册关联表失败!", zap.Error(err))
			return err
		}
		// 确保数据库表结构是最新的
		RegisterTables()
	}

	// 重新初始化定时任务
	Timer()

	global.AppLog.Info("系统配置重新加载完成")
	return nil
}
