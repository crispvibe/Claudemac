package admin

type RoleButtonBinding struct {
	RoleID             uint             `gorm:"column:role_id;comment:角色ID"`
	NavigationEntryID  uint             `gorm:"column:navigation_entry_id;comment:菜单ID"`
	NavigationActionID uint             `gorm:"column:navigation_action_id;comment:菜单按钮ID"`
	NavigationAction   NavigationAction `gorm:"foreignKey:NavigationActionID;references:ID;comment:按钮详情"`
}

func (RoleButtonBinding) TableName() string {
	return "role_button_bindings"
}