package internal

import (
	"time"

	"heyu/server/setting"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
	"gorm.io/gorm/schema"
)

var Gorm = new(_gorm)

type _gorm struct{}

// Config gorm 自定义配置
func (g *_gorm) Config(general setting.GeneralDB) *gorm.Config {
	return &gorm.Config{
		Logger: logger.New(NewWriter(general), logger.Config{
			SlowThreshold: 200 * time.Millisecond,
			LogLevel:      general.LogLevel(),
			Colorful:      true,
		}),
		NamingStrategy: schema.NamingStrategy{
			TablePrefix:   general.Prefix,
			SingularTable: general.Singular,
		},
		DisableForeignKeyConstraintWhenMigrating: true,
	}
}
