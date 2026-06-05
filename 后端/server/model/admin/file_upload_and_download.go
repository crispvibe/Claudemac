package admin

import "heyu/server/global"

type FileUploadAndDownload struct {
	global.BaseModel
	Name       string `json:"name" gorm:"comment:文件名;size:255"`
	Url        string `json:"url" gorm:"comment:文件访问地址;size:500"`
	Key        string `json:"key" gorm:"comment:文件存储键;size:255;index"`
	ClassId    uint   `json:"classId" gorm:"comment:分类ID;default:0;index"`
	Mime       string `json:"mime" gorm:"comment:文件MIME;size:128"`
	Ext        string `json:"ext" gorm:"comment:文件扩展名;size:32"`
	Size       int64  `json:"size" gorm:"comment:文件大小"`
	UploadedBy uint   `json:"uploadedBy" gorm:"comment:上传用户ID;index"`
}

func (FileUploadAndDownload) TableName() string {
	return "file_upload_and_downloads"
}
