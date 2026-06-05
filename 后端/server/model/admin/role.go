package admin

import (
	"time"
)

type Role struct {
	CreatedAt       time.Time       // 创建时间
	UpdatedAt       time.Time       // 更新时间
	DeletedAt       *time.Time      `sql:"index"`
	RoleID          uint            `json:"roleId" gorm:"column:role_id;not null;unique;primary_key;comment:角色ID;size:90"`     // 角色ID
	RoleName        string          `json:"roleName" gorm:"comment:角色名"`                                                       // 角色名
	ParentId        *uint           `json:"parentId" gorm:"column:parent_role_id;comment:父角色ID"`                              // 父角色ID
	DataRoleIds     []*Role         `json:"dataRoleIds" gorm:"many2many:role_data_scopes;foreignKey:RoleID;joinForeignKey:RoleID;references:RoleID;joinReferences:ScopeRoleID"`
	Children        []Role          `json:"children" gorm:"-"`
	NavigationEntries []NavigationEntry `json:"menus" gorm:"many2many:role_navigation_entries;foreignKey:RoleID;joinForeignKey:RoleID;references:ID;joinReferences:NavigationEntryID"`
	Users             []Account         `json:"-" gorm:"many2many:account_roles;foreignKey:RoleID;joinForeignKey:RoleID;references:ID;joinReferences:AccountID"`
	DefaultEntry    string          `json:"defaultEntry" gorm:"column:default_entry;comment:默认菜单;default:dashboard"`  // 默认菜单(默认dashboard)
}

func (Role) TableName() string {
	return "roles"
}