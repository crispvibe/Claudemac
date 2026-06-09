package admin

import "heyu/server/global"

type AttachmentCategory struct {
	global.BaseModel
	Name     string               `json:"name" gorm:"comment:附件分类名称;size:100"`
	Pid      uint                 `json:"pid" gorm:"comment:父级分类ID;default:0;index"`
	Sort     int                  `json:"sort" gorm:"comment:排序;default:0"`
	Children []AttachmentCategory `json:"children" gorm:"-"`
}

func (AttachmentCategory) TableName() string {
	return "attachment_categories"
}
