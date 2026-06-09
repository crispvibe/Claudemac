package admin

import "heyu/server/global"

type NavigationAction struct {
	global.BaseModel
	Name              string `json:"name" gorm:"comment:按钮关键key"`
	Desc              string `json:"desc" gorm:"按钮备注"`
	NavigationEntryID uint   `json:"navigationEntryId" gorm:"column:navigation_entry_id;comment:菜单ID"`
}

func (NavigationAction) TableName() string {
	return "navigation_actions"
}
