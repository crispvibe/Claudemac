package initialize

import (
	"heyu/server/setting"
	"heyu/server/global"
	"gorm.io/gorm"
)

const sys = "system"

func DBList() {
	dbMap := make(map[string]*gorm.DB)
	for _, info := range global.AppConfig.DBList {
		if info.Disable {
			continue
		}
		if info.Type != "mysql" {
			continue
		}
		dbMap[info.AliasName] = GormMysqlByConfig(setting.Mysql{GeneralDB: info.GeneralDB})
	}
	// 做特殊判断,是否有迁移
	// 适配低版本迁移多数据库版本
	if primaryDB, ok := dbMap[sys]; ok {
		global.AppDB = primaryDB
	}
	global.AppDBList = dbMap
}
