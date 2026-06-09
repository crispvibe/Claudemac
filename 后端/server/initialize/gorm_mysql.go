package initialize

import (
	"heyu/server/setting"
	"heyu/server/global"
	"heyu/server/initialize/internal"
	_ "github.com/go-sql-driver/mysql"
	"gorm.io/driver/mysql"
	"gorm.io/gorm"
)

// GormMysql 初始化Mysql数据库
func GormMysql() *gorm.DB {
	m := global.AppConfig.Mysql
	return initMysqlDatabase(m)
}

// GormMysqlByConfig 通过传入配置初始化Mysql数据库
func GormMysqlByConfig(m setting.Mysql) *gorm.DB {
	return initMysqlDatabase(m)
}

// initMysqlDatabase 初始化Mysql数据库的辅助函数
func initMysqlDatabase(m setting.Mysql) *gorm.DB {
	if m.Dbname == "" {
		return nil
	}

	mysqlConfig := mysql.Config{
		DSN:                       m.Dsn(), // DSN data source name
		DefaultStringSize:         191,     // string 类型字段的默认长度
		SkipInitializeWithVersion: false,   // 根据版本自动配置
	}
	// 数据库配置
	general := m.GeneralDB
	if db, err := gorm.Open(mysql.New(mysqlConfig), internal.Gorm.Config(general)); err != nil {
		panic(err)
	} else {
		db.InstanceSet("gorm:table_options", "ENGINE="+m.Engine)
		sqlDB, _ := db.DB()
		sqlDB.SetMaxIdleConns(m.MaxIdleConns)
		sqlDB.SetMaxOpenConns(m.MaxOpenConns)
		return db
	}
}
