package admin

import (
	"errors"

	"heyu/server/global"
	"heyu/server/model/admin"
	"gorm.io/gorm"
)

type BaseMenuService struct{}

//@function: DeleteBaseMenu
//@description: 删除基础路由
//@param: id float64
//@return: err error

var BaseMenuServiceApp = new(BaseMenuService)

func (baseMenuService *BaseMenuService) DeleteBaseMenu(id int) (err error) {
	err = global.AppDB.First(&admin.NavigationEntry{}, "parent_id = ?", id).Error
	if err == nil {
		return errors.New("此菜单存在子菜单不可删除")
	}
	var menu admin.NavigationEntry
	err = global.AppDB.First(&menu, id).Error
	if err != nil {
		return errors.New("记录不存在")
	}
	err = global.AppDB.First(&admin.Role{}, "default_entry = ?", menu.Name).Error
	if err == nil {
		return errors.New("此菜单有角色正在作为首页，不可删除")
	}
	return global.AppDB.Transaction(func(tx *gorm.DB) error {

		err = tx.Delete(&admin.NavigationEntry{}, "id = ?", id).Error
		if err != nil {
			return err
		}

		err = tx.Delete(&admin.NavigationParameter{}, "navigation_entry_id = ?", id).Error
		if err != nil {
			return err
		}

		err = tx.Delete(&admin.NavigationAction{}, "navigation_entry_id = ?", id).Error
		if err != nil {
			return err
		}
		err = tx.Delete(&admin.RoleButtonBinding{}, "navigation_entry_id = ?", id).Error
		if err != nil {
			return err
		}

		err = tx.Delete(&admin.RoleNavigationBinding{}, "navigation_entry_id = ?", id).Error
		if err != nil {
			return err
		}
		return nil
	})

}

//@function: UpdateBaseMenu
//@description: 更新路由
//@param: menu model.NavigationEntry
//@return: err error

func (baseMenuService *BaseMenuService) UpdateBaseMenu(menu admin.NavigationEntry) (err error) {
	var oldMenu admin.NavigationEntry
	menu.Component = admin.NormalizeComponentIdentifier(menu.Component)
	upDateMap := make(map[string]interface{})
	upDateMap["keep_alive"] = menu.KeepAlive
	upDateMap["transition_type"] = menu.TransitionType
	upDateMap["close_tab"] = menu.CloseTab
	upDateMap["default_menu"] = menu.DefaultMenu
	upDateMap["parent_id"] = menu.ParentId
	upDateMap["path"] = menu.Path
	upDateMap["name"] = menu.Name
	upDateMap["hidden"] = menu.Hidden
	upDateMap["component"] = menu.Component
	upDateMap["title"] = menu.Title
	upDateMap["active_name"] = menu.ActiveName
	upDateMap["icon"] = menu.Icon
	upDateMap["sort"] = menu.Sort

	err = global.AppDB.Transaction(func(tx *gorm.DB) error {
		tx.Where("id = ?", menu.ID).Find(&oldMenu)
		if oldMenu.Name != menu.Name {
			if !errors.Is(tx.Where("id <> ? AND name = ?", menu.ID, menu.Name).First(&admin.NavigationEntry{}).Error, gorm.ErrRecordNotFound) {
				global.AppLog.Debug("存在相同name修改失败")
				return errors.New("存在相同name修改失败")
			}
		}
		txErr := tx.Unscoped().Delete(&admin.NavigationParameter{}, "navigation_entry_id = ?", menu.ID).Error
		if txErr != nil {
			global.AppLog.Debug(txErr.Error())
			return txErr
		}
		txErr = tx.Unscoped().Delete(&admin.NavigationAction{}, "navigation_entry_id = ?", menu.ID).Error
		if txErr != nil {
			global.AppLog.Debug(txErr.Error())
			return txErr
		}
		if len(menu.Parameters) > 0 {
			for k := range menu.Parameters {
				menu.Parameters[k].NavigationEntryID = menu.ID
			}
			txErr = tx.Create(&menu.Parameters).Error
			if txErr != nil {
				global.AppLog.Debug(txErr.Error())
				return txErr
			}
		}

		if len(menu.Actions) > 0 {
			for k := range menu.Actions {
				menu.Actions[k].NavigationEntryID = menu.ID
			}
			txErr = tx.Create(&menu.Actions).Error
			if txErr != nil {
				global.AppLog.Debug(txErr.Error())
				return txErr
			}
		}

		txErr = tx.Model(&oldMenu).Updates(upDateMap).Error
		if txErr != nil {
			global.AppLog.Debug(txErr.Error())
			return txErr
		}
		return nil
	})
	return err
}

//@function: GetBaseMenuById
//@description: 返回当前选中menu
//@param: id float64
//@return: menu admin.NavigationEntry, err error

func (baseMenuService *BaseMenuService) GetBaseMenuById(id int) (menu admin.NavigationEntry, err error) {
	err = global.AppDB.Preload("Actions").Preload("Parameters").Where("id = ?", id).First(&menu).Error
	menu.Component = admin.NormalizeComponentIdentifier(menu.Component)
	return
}
