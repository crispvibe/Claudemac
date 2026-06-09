package initialize

import (
	"os"

	"heyu/server/global"
	"heyu/server/model/admin"

	gormadapter "github.com/casbin/gorm-adapter/v3"
	"go.uber.org/zap"
	"gorm.io/gorm"
)

func Gorm() *gorm.DB {
	global.AppActiveDBName = &global.AppConfig.Mysql.Dbname
	return GormMysql()
}

func RegisterTables() {
	if global.AppConfig.System.DisableAutoMigrate {
		global.AppLog.Info("auto-migrate is disabled, skipping table registration")
		return
	}

	db := global.AppDB
	err := db.AutoMigrate(
		admin.APICatalogEntry{},
		admin.IgnoredAPIEntry{},
		admin.Account{},
		admin.NavigationEntry{},
		admin.JwtBlacklist{},
		admin.Role{},
		admin.OperationRecord{},
		admin.NavigationParameter{},
		admin.NavigationAction{},
		admin.RoleButtonBinding{},
		admin.LoginLog{},
		admin.AttachmentCategory{},
		admin.FileUploadAndDownload{},
		admin.APIAccessToken{},
		admin.ExportTemplate{},
		admin.AccountRole{},
		admin.RoleNavigationBinding{},
		admin.RoleDataScope{},
		admin.SecurityNotification{},
		admin.SecurityNotificationRead{},
		gormadapter.CasbinRule{},
	)
	if err != nil {
		global.AppLog.Error("register table failed", zap.Error(err))
		os.Exit(0)
	}

	err = bizModel()

	if err != nil {
		global.AppLog.Error("register biz_table failed", zap.Error(err))
		os.Exit(0)
	}

	bootstrapLocalBaselineData(db)
	global.AppLog.Info("register table success")
}
