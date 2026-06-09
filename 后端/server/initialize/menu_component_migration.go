package initialize

import (
	"heyu/server/global"
	"heyu/server/model/admin"

	"go.uber.org/zap"
	"gorm.io/gorm"
)

func NormalizeMenuComponentIdentifiers() error {
	if global.AppDB == nil {
		return nil
	}

	var menus []admin.NavigationEntry
	if err := global.AppDB.Select("id", "component").Find(&menus).Error; err != nil {
		return err
	}

	updated := 0
	err := global.AppDB.Transaction(func(tx *gorm.DB) error {
		for _, menu := range menus {
			normalized := admin.NormalizeComponentIdentifier(menu.Component)
			if normalized == "" || normalized == menu.Component {
				continue
			}
			if err := tx.Model(&admin.NavigationEntry{}).Where("id = ?", menu.ID).Update("component", normalized).Error; err != nil {
				return err
			}
			updated++
		}
		return nil
	})
	if err != nil {
		return err
	}

	global.AppLog.Info("migrated menu component identifiers", zap.Int("updated", updated))
	return nil
}
