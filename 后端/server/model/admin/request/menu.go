package request

import (
	"heyu/server/global"
	"heyu/server/model/admin"
)

// AssignRoleNavigationRequest add menu role binding request structure
type AssignRoleNavigationRequest struct {
	Menus  []admin.NavigationEntry `json:"menus"`
	RoleID uint                 `json:"roleId"` // 角色ID
}

func DefaultMenu() []admin.NavigationEntry {
	return []admin.NavigationEntry{{
		BaseModel: global.BaseModel{ID: 1},
		ParentId:  0,
		Path:      "dashboard",
		Name:      "dashboard",
		Component: admin.BuildComponentIdentifierFromLegacyPath("view/dashboard/index.vue"),
		Sort:      1,
		Meta: admin.Meta{
			Title: "后台首页",
			Icon:  "setting",
		},
	}}
}
