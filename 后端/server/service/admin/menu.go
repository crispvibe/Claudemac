package admin

import (
	"errors"
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/admin"
	"gorm.io/gorm"
)

func normalizeBaseMenusComponent(menus []admin.NavigationEntry) {
	for i := range menus {
		menus[i].Component = admin.NormalizeComponentIdentifier(menus[i].Component)
		if len(menus[i].Children) > 0 {
			normalizeBaseMenusComponent(menus[i].Children)
		}
	}
}

func normalizeMenusComponent(menus []admin.NavigationMenu) {
	for i := range menus {
		menus[i].Component = admin.NormalizeComponentIdentifier(menus[i].Component)
		if len(menus[i].Children) > 0 {
			normalizeMenusComponent(menus[i].Children)
		}
	}
}

//@function: getMenuTreeMap
//@description: 获取路由总树map
//@param: roleId string
//@return: treeMap map[string][]admin.NavigationMenu, err error

type MenuService struct{}

var MenuServiceApp = new(MenuService)

func (menuService *MenuService) getMenuTreeMap(roleID uint) (treeMap map[uint][]admin.NavigationMenu, err error) {
	var allMenus []admin.NavigationMenu
	var baseMenu []admin.NavigationEntry
	var btns []admin.RoleButtonBinding
	treeMap = make(map[uint][]admin.NavigationMenu)

	var roleMenuBindings []admin.RoleNavigationBinding
	err = global.AppDB.Where("role_id = ?", roleID).Find(&roleMenuBindings).Error
	if err != nil {
		return
	}

	var MenuIds []uint

	for i := range roleMenuBindings {
		MenuIds = append(MenuIds, roleMenuBindings[i].MenuId)
	}

	err = global.AppDB.Where("id in (?)", MenuIds).Order("sort").Preload("Parameters").Find(&baseMenu).Error
	if err != nil {
		return
	}

	for i := range baseMenu {
		allMenus = append(allMenus, admin.NavigationMenu{
			NavigationEntry: baseMenu[i],
			RoleID:          roleID,
			MenuId:          baseMenu[i].ID,
			Parameters:      baseMenu[i].Parameters,
		})
	}

	err = global.AppDB.Where("role_id = ?", roleID).Preload("NavigationAction").Find(&btns).Error
	if err != nil {
		return
	}
	var btnMap = make(map[uint]map[string]uint)
	for _, v := range btns {
		if btnMap[v.NavigationEntryID] == nil {
			btnMap[v.NavigationEntryID] = make(map[string]uint)
		}
		btnMap[v.NavigationEntryID][v.NavigationAction.Name] = roleID
	}
	for _, v := range allMenus {
		v.Btns = btnMap[v.NavigationEntry.ID]
		treeMap[v.ParentId] = append(treeMap[v.ParentId], v)
	}
	return treeMap, err
}

//@function: GetMenuTree
//@description: 获取动态菜单树
//@param: roleId string
//@return: menus []admin.NavigationMenu, err error

func (menuService *MenuService) GetMenuTree(roleID uint) (menus []admin.NavigationMenu, err error) {
	menuTree, err := menuService.getMenuTreeMap(roleID)
	menus = menuTree[0]
	for i := 0; i < len(menus); i++ {
		err = menuService.getChildrenList(&menus[i], menuTree)
	}
	normalizeMenusComponent(menus)
	return menus, err
}

//@function: getChildrenList
//@description: 获取子菜单
//@param: menu *model.NavigationMenu, treeMap map[string][]model.NavigationMenu
//@return: err error

func (menuService *MenuService) getChildrenList(menu *admin.NavigationMenu, treeMap map[uint][]admin.NavigationMenu) (err error) {
	menu.Children = treeMap[menu.MenuId]
	for i := 0; i < len(menu.Children); i++ {
		err = menuService.getChildrenList(&menu.Children[i], treeMap)
	}
	return err
}

//@function: GetInfoList
//@description: 获取路由分页
//@return: list interface{}, total int64,err error

func (menuService *MenuService) GetInfoList(roleID uint) (list interface{}, err error) {
	var menuList []admin.NavigationEntry
	treeMap, err := menuService.getBaseMenuTreeMap(roleID)
	menuList = treeMap[0]
	for i := 0; i < len(menuList); i++ {
		err = menuService.getBaseChildrenList(&menuList[i], treeMap)
	}
	normalizeBaseMenusComponent(menuList)
	return menuList, err
}

//@function: getBaseChildrenList
//@description: 获取菜单的子菜单
//@param: menu *model.NavigationEntry, treeMap map[string][]model.NavigationEntry
//@return: err error

func (menuService *MenuService) getBaseChildrenList(menu *admin.NavigationEntry, treeMap map[uint][]admin.NavigationEntry) (err error) {
	menu.Children = treeMap[menu.ID]
	for i := 0; i < len(menu.Children); i++ {
		err = menuService.getBaseChildrenList(&menu.Children[i], treeMap)
	}
	return err
}

//@function: AddBaseMenu
//@description: 添加基础路由
//@param: menu model.NavigationEntry
//@return: error

func (menuService *MenuService) AddBaseMenu(menu admin.NavigationEntry) error {
	menu.Component = admin.NormalizeComponentIdentifier(menu.Component)
	return global.AppDB.Transaction(func(tx *gorm.DB) error {
		// 检查name是否重复
		if !errors.Is(tx.Where("name = ?", menu.Name).First(&admin.NavigationEntry{}).Error, gorm.ErrRecordNotFound) {
			return errors.New("存在重复name，请修改name")
		}

		if menu.ParentId != 0 {
			// 检查父菜单是否存在
			var parentMenu admin.NavigationEntry
			if err := tx.First(&parentMenu, menu.ParentId).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return errors.New("父菜单不存在")
				}
				return err
			}

			// 检查父菜单下现有子菜单数量
			var existingChildrenCount int64
			err := tx.Model(&admin.NavigationEntry{}).Where("parent_id = ?", menu.ParentId).Count(&existingChildrenCount).Error
			if err != nil {
				return err
			}

			// 如果父菜单原本是叶子菜单（没有子菜单），现在要变成枝干菜单，需要清空其权限分配
			if existingChildrenCount == 0 {
				// 检查父菜单是否被其他角色设置为首页
				var defaultEntryCount int64
				err := tx.Model(&admin.Role{}).Where("default_entry = ?", parentMenu.Name).Count(&defaultEntryCount).Error
				if err != nil {
					return err
				}
				if defaultEntryCount > 0 {
					return errors.New("父菜单已被其他角色的首页占用，请先释放父菜单的首页权限")
				}

				// 清空父菜单的所有权限分配
				err = tx.Where("navigation_entry_id = ?", menu.ParentId).Delete(&admin.RoleNavigationBinding{}).Error
				if err != nil {
					return err
				}
			}
		}

		// 创建菜单
		return tx.Create(&menu).Error
	})
}

//@function: getBaseMenuTreeMap
//@description: 获取路由总树map
//@return: treeMap map[string][]admin.NavigationEntry, err error

func (menuService *MenuService) getBaseMenuTreeMap(roleID uint) (treeMap map[uint][]admin.NavigationEntry, err error) {
	parentRoleID, err := RoleServiceApp.GetParentRoleID(roleID)
	if err != nil {
		return nil, err
	}

	var allMenus []admin.NavigationEntry
	treeMap = make(map[uint][]admin.NavigationEntry)
	db := global.AppDB.Order("sort").Preload("Actions").Preload("Parameters")

	// 当开启了严格的树角色并且父角色不为0时需要进行菜单筛选
	if global.AppConfig.System.UseStrictAuth && parentRoleID != 0 {
		var roleMenuBindings []admin.RoleNavigationBinding
		err = global.AppDB.Where("role_id = ?", roleID).Find(&roleMenuBindings).Error
		if err != nil {
			return nil, err
		}
		var menuIds []uint
		for i := range roleMenuBindings {
			menuIds = append(menuIds, roleMenuBindings[i].MenuId)
		}
		db = db.Where("id in (?)", menuIds)
	}

	err = db.Find(&allMenus).Error
	for _, v := range allMenus {
		treeMap[v.ParentId] = append(treeMap[v.ParentId], v)
	}
	return treeMap, err
}

//@function: GetBaseMenuTree
//@description: 获取基础路由树
//@return: menus []admin.NavigationEntry, err error

func (menuService *MenuService) GetBaseMenuTree(roleID uint) (menus []admin.NavigationEntry, err error) {
	treeMap, err := menuService.getBaseMenuTreeMap(roleID)
	menus = treeMap[0]
	for i := 0; i < len(menus); i++ {
		err = menuService.getBaseChildrenList(&menus[i], treeMap)
	}
	normalizeBaseMenusComponent(menus)
	return menus, err
}

//@function: AssignRoleNavigation
//@description: 为角色增加menu树
//@param: menus []model.NavigationEntry, roleId string
//@return: err error

func (menuService *MenuService) AssignRoleNavigation(menus []admin.NavigationEntry, adminRoleID, roleID uint) (err error) {
	var role admin.Role
	role.RoleID = roleID
	role.NavigationEntries = menus

	err = RoleServiceApp.CheckRoleScope(adminRoleID, roleID)
	if err != nil {
		return err
	}

	var adminRole admin.Role
	_ = global.AppDB.First(&adminRole, "role_id = ?", adminRoleID).Error
	var menuIds []uint

	// 当开启了严格的树角色并且父角色不为0时需要进行菜单筛选
	if global.AppConfig.System.UseStrictAuth && *adminRole.ParentId != 0 {
		var roleMenuBindings []admin.RoleNavigationBinding
		err = global.AppDB.Where("role_id = ?", adminRoleID).Find(&roleMenuBindings).Error
		if err != nil {
			return err
		}
		for i := range roleMenuBindings {
			menuIds = append(menuIds, roleMenuBindings[i].MenuId)
		}

		for i := range menus {
			hasMenu := false
			for j := range menuIds {
				if menus[i].ID == menuIds[j] {
					hasMenu = true
				}
			}
			if !hasMenu {
				return errors.New("添加失败,请勿跨级操作")
			}
		}
	}

	err = RoleServiceApp.SetRoleNavigation(&role)
	return err
}

//@function: GetRoleNavigation
//@description: 查看当前角色树
//@param: info *request.GetRoleId
//@return: menus []admin.NavigationMenu, err error

func (menuService *MenuService) GetRoleNavigation(info *request.GetRoleId) (menus []admin.NavigationMenu, err error) {
	var baseMenu []admin.NavigationEntry
	var roleMenuBindings []admin.RoleNavigationBinding
	err = global.AppDB.Where("role_id = ?", info.RoleID).Find(&roleMenuBindings).Error
	if err != nil {
		return
	}

	var MenuIds []uint

	for i := range roleMenuBindings {
		MenuIds = append(MenuIds, roleMenuBindings[i].MenuId)
	}

	err = global.AppDB.Where("id in (?) ", MenuIds).Order("sort").Find(&baseMenu).Error

	for i := range baseMenu {
		baseMenu[i].Component = admin.NormalizeComponentIdentifier(baseMenu[i].Component)
		menus = append(menus, admin.NavigationMenu{
			NavigationEntry: baseMenu[i],
			RoleID:          info.RoleID,
			MenuId:          baseMenu[i].ID,
			Parameters:      baseMenu[i].Parameters,
		})
	}
	return menus, err
}

// EnsureUserDefaultEntry 用户角色默认路由检查
//
func (menuService *MenuService) EnsureUserDefaultEntry(user *admin.Account) {
	var menuIds []uint
	err := global.AppDB.Model(&admin.RoleNavigationBinding{}).Where("role_id = ?", user.PrimaryRoleID).Pluck("navigation_entry_id", &menuIds).Error
	if err != nil {
		return
	}
	var am admin.NavigationEntry
	err = global.AppDB.First(&am, "name = ? and id in (?)", user.PrimaryRole.DefaultEntry, menuIds).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		user.PrimaryRole.DefaultEntry = "404"
	}
}
