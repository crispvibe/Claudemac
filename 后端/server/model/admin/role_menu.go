package admin

type NavigationMenu struct {
	NavigationEntry
	MenuId     uint                   `json:"menuId" gorm:"comment:菜单ID"`
	RoleID     uint                   `json:"-" gorm:"comment:角色ID"`
	Children   []NavigationMenu       `json:"children" gorm:"-"`
	Parameters []NavigationParameter  `json:"parameters" gorm:"foreignKey:NavigationEntryID;references:MenuId"`
	Btns       map[string]uint        `json:"btns" gorm:"-"`
}

type RoleNavigationBinding struct {
	MenuId uint `json:"menuId" gorm:"primaryKey;comment:菜单ID;column:navigation_entry_id"`
	RoleID uint `json:"-" gorm:"primaryKey;comment:角色ID;column:role_id"`
}

func (s RoleNavigationBinding) TableName() string {
	return "role_navigation_entries"
}