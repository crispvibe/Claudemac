package admin

import (
	"heyu/server/global"
)

type NavigationEntry struct {
	global.BaseModel
	MenuLevel     uint                   `json:"-"`
	ParentId      uint                   `json:"parentId" gorm:"comment:父菜单ID"`          // 父菜单ID
	Path          string                 `json:"path" gorm:"comment:路由path"`              // 路由path
	Name          string                 `json:"name" gorm:"comment:路由name"`              // 路由name
	Hidden        bool                   `json:"hidden" gorm:"comment:是否在列表隐藏"`      // 是否在列表隐藏
	Component     string                 `json:"component" gorm:"comment:前端页面组件标识"` // 前端页面组件标识
	Sort          int                    `json:"sort" gorm:"comment:排序标记"`              // 排序标记
	Meta          `json:"meta" gorm:"embedded"`                                             // 附加属性
	Roles         []Role                 `json:"roles" gorm:"many2many:role_navigation_entries;foreignKey:ID;joinForeignKey:NavigationEntryID;references:RoleID;joinReferences:RoleID"`
	Children      []NavigationEntry      `json:"children" gorm:"-"`
	Parameters    []NavigationParameter  `json:"parameters"`
	Actions       []NavigationAction     `json:"menuBtn"`
}

type Meta struct {
	ActiveName     string `json:"activeName" gorm:"comment:高亮菜单"`
	KeepAlive      bool   `json:"keepAlive" gorm:"comment:是否缓存"`                 // 是否缓存
	DefaultMenu    bool   `json:"defaultMenu" gorm:"comment:是否是基础路由（开发中）"` // 是否是基础路由（开发中）
	Title          string `json:"title" gorm:"comment:菜单名"`                       // 菜单名
	Icon           string `json:"icon" gorm:"comment:菜单图标"`                      // 菜单图标
	CloseTab       bool   `json:"closeTab" gorm:"comment:自动关闭tab"`               // 自动关闭tab
	TransitionType string `json:"transitionType" gorm:"comment:路由切换动画"`        // 路由切换动画
}

type NavigationParameter struct {
	global.BaseModel
	NavigationEntryID uint   `gorm:"column:navigation_entry_id"`
	Type              string `json:"type" gorm:"comment:地址栏携带参数为params还是query"` // 地址栏携带参数为params还是query
	Key               string `json:"key" gorm:"comment:地址栏携带参数的key"`              // 地址栏携带参数的key
	Value             string `json:"value" gorm:"comment:地址栏携带参数的值"`             // 地址栏携带参数的值
}

func (NavigationEntry) TableName() string {
	return "navigation_entries"
}

func (NavigationParameter) TableName() string {
	return "navigation_parameters"
}

// 兼容别名，便于存量代码渐进迁移，不影响 GORM / JSON 行为。