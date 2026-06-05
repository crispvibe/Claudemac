package admin

import (
	"errors"
	"strconv"

	systemReq "heyu/server/model/admin/request"

	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
	"heyu/server/model/admin/response"
	"gorm.io/gorm"
)

var ErrRoleExistence = errors.New("存在相同角色id")

//@function: CreateRole
//@description: 创建一个角色
//@param: auth model.Role
//@return: role admin.Role, err error

type RoleService struct{}

var RoleServiceApp = new(RoleService)

func (roleService *RoleService) CreateRole(auth admin.Role) (role admin.Role, err error) {

	if err = global.AppDB.Where("role_id = ?", auth.RoleID).First(&admin.Role{}).Error; !errors.Is(err, gorm.ErrRecordNotFound) {
		return auth, ErrRoleExistence
	}

	e := global.AppDB.Transaction(func(tx *gorm.DB) error {

		if err = tx.Create(&auth).Error; err != nil {
			return err
		}

		auth.NavigationEntries = systemReq.DefaultMenu()
		if err = tx.Model(&auth).Association("NavigationEntries").Replace(&auth.NavigationEntries); err != nil {
			return err
		}
		casbinInfos := systemReq.DefaultCasbin()
		roleKey := strconv.Itoa(int(auth.RoleID))
		rules := [][]string{}
		for _, v := range casbinInfos {
			rules = append(rules, []string{roleKey, v.Path, v.Method})
		}
		return CasbinServiceApp.AddPolicies(tx, rules)
	})

	return auth, e
}

//@function: CopyRole
//@description: 复制一个角色
//@param: copyInfo response.RoleCopyResponse
//@return: role admin.Role, err error


func (roleService *RoleService) CopyRole(adminRoleID uint, copyInfo response.RoleCopyResponse) (role admin.Role, err error) {
	var roleBox admin.Role
	if !errors.Is(global.AppDB.Where("role_id = ?", copyInfo.Role.RoleID).First(&roleBox).Error, gorm.ErrRecordNotFound) {
		return role, ErrRoleExistence
	}
	copyInfo.Role.Children = []admin.Role{}
	menus, err := MenuServiceApp.GetRoleNavigation(&request.GetRoleId{RoleID: copyInfo.OldRoleID})
	if err != nil {
		return
	}
	var baseMenu []admin.NavigationEntry
	for _, v := range menus {
		intNum := v.MenuId
		v.NavigationEntry.ID = uint(intNum)
		baseMenu = append(baseMenu, v.NavigationEntry)
	}
	copyInfo.Role.NavigationEntries = baseMenu
	err = global.AppDB.Create(&copyInfo.Role).Error
	if err != nil {
		return
	}

	var btns []admin.RoleButtonBinding

	err = global.AppDB.Find(&btns, "role_id = ?", copyInfo.OldRoleID).Error
	if err != nil {
		return
	}
	if len(btns) > 0 {
		for i := range btns {
			btns[i].RoleID = copyInfo.Role.RoleID
		}
		err = global.AppDB.Create(&btns).Error

		if err != nil {
			return
		}
	}
	paths := CasbinServiceApp.GetPolicyPathByRoleID(copyInfo.OldRoleID)
	err = CasbinServiceApp.UpdateCasbin(adminRoleID, copyInfo.Role.RoleID, paths)
	if err != nil {
		_ = roleService.DeleteRole(&copyInfo.Role)
	}
	return copyInfo.Role, err
}

//@function: UpdateRole
//@description: 更改一个角色
//@param: auth model.Role
//@return: role admin.Role, err error

func (roleService *RoleService) UpdateRole(auth admin.Role) (role admin.Role, err error) {
	var oldRole admin.Role
	err = global.AppDB.Where("role_id = ?", auth.RoleID).First(&oldRole).Error
	if err != nil {
		global.AppLog.Debug(err.Error())
		return admin.Role{}, errors.New("查询角色数据失败")
	}
	err = global.AppDB.Model(&oldRole).Updates(&auth).Error
	return auth, err
}

//@function: DeleteRole
//@description: 删除角色
//@param: auth *model.Role
//@return: err error

func (roleService *RoleService) DeleteRole(auth *admin.Role) error {
	if errors.Is(global.AppDB.Preload("Users").First(&auth).Error, gorm.ErrRecordNotFound) {
		return errors.New("该角色不存在")
	}
	if len(auth.Users) != 0 {
		return errors.New("此角色有用户正在使用禁止删除")
	}
	if !errors.Is(global.AppDB.Where("primary_role_id = ?", auth.RoleID).First(&admin.Account{}).Error, gorm.ErrRecordNotFound) {
		return errors.New("此角色有用户正在使用禁止删除")
	}
	if !errors.Is(global.AppDB.Where("parent_role_id = ?", auth.RoleID).First(&admin.Role{}).Error, gorm.ErrRecordNotFound) {
		return errors.New("此角色存在子角色不允许删除")
	}

	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		var err error
		if err = tx.Preload("NavigationEntries").Preload("DataRoleIds").Where("role_id = ?", auth.RoleID).First(auth).Unscoped().Delete(auth).Error; err != nil {
			return err
		}

		if len(auth.NavigationEntries) > 0 {
			if err = tx.Model(auth).Association("NavigationEntries").Delete(auth.NavigationEntries); err != nil {
				return err
			}
		}
		if len(auth.DataRoleIds) > 0 {
			if err = tx.Model(auth).Association("DataRoleIds").Delete(auth.DataRoleIds); err != nil {
				return err
			}
		}

		if err = tx.Delete(&admin.AccountRole{}, "role_id = ?", auth.RoleID).Error; err != nil {
			return err
		}
		if err = tx.Where("role_id = ?", auth.RoleID).Delete(&[]admin.RoleButtonBinding{}).Error; err != nil {
			return err
		}

		roleKey := strconv.Itoa(int(auth.RoleID))

		if err = CasbinServiceApp.RemoveFilteredPolicy(tx, roleKey); err != nil {
			return err
		}

		return nil
	})
}

//@function: GetRoleList
//@description: 分页获取数据
//@param: info request.PageInfo
//@return: list interface{}, total int64, err error

func (roleService *RoleService) GetRoleList(roleID uint) (list []admin.Role, err error) {
	var currentRole admin.Role
	err = global.AppDB.Where("role_id = ?", roleID).First(&currentRole).Error
	if err != nil {
		return nil, err
	}
	var roles []admin.Role
	db := global.AppDB.Model(&admin.Role{})
	if global.AppConfig.System.UseStrictAuth {
		// 当开启了严格树形结构后
		if *currentRole.ParentId == 0 {
			// 只有顶级角色可以修改自己的权限和以下权限
			err = db.Preload("DataRoleIds").Where("role_id = ?", roleID).Find(&roles).Error
		} else {
			// 非顶级角色只能修改以下权限
			err = db.Preload("DataRoleIds").Where("parent_role_id = ?", roleID).Find(&roles).Error
		}
	} else {
		err = db.Preload("DataRoleIds").Where("parent_role_id = ?", "0").Find(&roles).Error
	}

	for k := range roles {
		err = roleService.findChildrenRole(&roles[k])
	}
	return roles, err
}

//@function: GetRoleScopeIDs
//@description: 分页获取数据
//@param: info request.PageInfo
//@return: list interface{}, total int64, err error

func (roleService *RoleService) GetRoleScopeIDs(roleID uint) (list []uint, err error) {
	var role admin.Role
	_ = global.AppDB.First(&role, "role_id = ?", roleID).Error
	var childRoles []admin.Role
	err = global.AppDB.Preload("DataRoleIds").Where("parent_role_id = ?", roleID).Find(&childRoles).Error
	if len(childRoles) > 0 {
		for k := range childRoles {
			list = append(list, childRoles[k].RoleID)
			childrenList, err := roleService.GetRoleScopeIDs(childRoles[k].RoleID)
			if err == nil {
				list = append(list, childrenList...)
			}
		}
	}
	if *role.ParentId == 0 {
		list = append(list, roleID)
	}
	return list, err
}

func (roleService *RoleService) CheckRoleScope(roleID, targetID uint) (err error) {
	if !global.AppConfig.System.UseStrictAuth {
		return nil
	}
	roleIDs, err := roleService.GetRoleScopeIDs(roleID)
	if err != nil {
		return err
	}
	hasAuth := false
	for _, v := range roleIDs {
		if v == targetID {
			hasAuth = true
			break
		}
	}
	if !hasAuth {
		return errors.New("您提交的角色ID不合法")
	}
	return nil
}

//@function: GetRoleInfo
//@description: 获取所有角色信息
//@param: auth model.Role
//@return: role admin.Role, err error

func (roleService *RoleService) GetRoleInfo(auth admin.Role) (role admin.Role, err error) {
	err = global.AppDB.Preload("DataRoleIds").Where("role_id = ?", auth.RoleID).First(&role).Error
	return role, err
}

//@function: SetRoleDataScope
//@description: 设置角色资源权限
//@param: auth model.Role
//@return: error

func (roleService *RoleService) SetRoleDataScope(adminRoleID uint, auth admin.Role) error {
	var checkIDs []uint
	checkIDs = append(checkIDs, auth.RoleID)
	for i := range auth.DataRoleIds {
		checkIDs = append(checkIDs, auth.DataRoleIds[i].RoleID)
	}

	for i := range checkIDs {
		err := roleService.CheckRoleScope(adminRoleID, checkIDs[i])
		if err != nil {
			return err
		}
	}

	var s admin.Role
	global.AppDB.Preload("DataRoleIds").First(&s, "role_id = ?", auth.RoleID)
	err := global.AppDB.Model(&s).Association("DataRoleIds").Replace(&auth.DataRoleIds)
	return err
}

//@function: SetRoleNavigation
//@description: 菜单与角色绑定
//@param: auth *model.Role
//@return: error

func (roleService *RoleService) SetRoleNavigation(auth *admin.Role) error {
	var s admin.Role
	global.AppDB.Preload("NavigationEntries").First(&s, "role_id = ?", auth.RoleID)
	err := global.AppDB.Model(&s).Association("NavigationEntries").Replace(&auth.NavigationEntries)
	return err
}

//@function: findChildrenRole
//@description: 查询子角色
//@param: role *model.Role
//@return: err error

func (roleService *RoleService) findChildrenRole(role *admin.Role) (err error) {
	err = global.AppDB.Preload("DataRoleIds").Where("parent_role_id = ?", role.RoleID).Find(&role.Children).Error
	if len(role.Children) > 0 {
		for k := range role.Children {
			err = roleService.findChildrenRole(&role.Children[k])
		}
	}
	return err
}

func (roleService *RoleService) GetParentRoleID(roleID uint) (parentID uint, err error) {
	var role admin.Role
	err = global.AppDB.Where("role_id = ?", roleID).First(&role).Error
	if err != nil {
		return
	}
	return *role.ParentId, nil
}
