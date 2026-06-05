package admin

import (
	"errors"
	"heyu/server/global"
	"heyu/server/model/admin"
	"heyu/server/model/admin/request"
	"heyu/server/model/admin/response"
	"gorm.io/gorm"
)

type RoleButtonBindingService struct{}

var RoleButtonBindingServiceApp = new(RoleButtonBindingService)

func (a *RoleButtonBindingService) GetRoleButtonBindings(req request.RoleButtonBindingRequest) (res response.RoleButtonBindingResponse, err error) {
	var bindings []admin.RoleButtonBinding
	err = global.AppDB.Find(&bindings, "role_id = ? and navigation_entry_id = ?", req.RoleID, req.MenuID).Error
	if err != nil {
		return
	}
	var selected []uint
	for _, v := range bindings {
		selected = append(selected, v.NavigationActionID)
	}
	res.Selected = selected
	return res, err
}

func (a *RoleButtonBindingService) UpdateRoleButtonBindings(req request.RoleButtonBindingRequest) (err error) {
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var bindings []admin.RoleButtonBinding
		err = tx.Delete(&[]admin.RoleButtonBinding{}, "role_id = ? and navigation_entry_id = ?", req.RoleID, req.MenuID).Error
		if err != nil {
			return err
		}
		for _, v := range req.Selected {
			bindings = append(bindings, admin.RoleButtonBinding{
				RoleID:             req.RoleID,
				NavigationEntryID:  req.MenuID,
				NavigationActionID: v,
			})
		}
		if len(bindings) > 0 {
			err = tx.Create(&bindings).Error
		}
		if err != nil {
			return err
		}
		return err
	})
}

func (a *RoleButtonBindingService) CanRemoveRoleButtonBinding(ID string) (err error) {
	fErr := global.AppDB.First(&admin.RoleButtonBinding{}, "navigation_action_id = ?", ID).Error
	if errors.Is(fErr, gorm.ErrRecordNotFound) {
		return nil
	}
	return errors.New("此按钮正在被使用无法删除")
}
