package admin

import (
	"time"

	"heyu/server/global"
)

type APIAccessToken struct {
	global.BaseModel
	UserID    uint       `json:"userId" gorm:"column:user_id;comment:用户ID"`
	RoleID    uint       `json:"roleId" gorm:"column:role_id;comment:角色ID"`
	Token     string     `json:"token,omitempty" gorm:"column:token;type:text;comment:API Token"`
	Status    bool       `json:"status" gorm:"column:status;default:1;comment:状态"`
	ExpiresAt *time.Time `json:"expiresAt" gorm:"column:expires_at;comment:过期时间"`
	Remark    string     `json:"remark" gorm:"column:remark;comment:备注"`
}

func (APIAccessToken) TableName() string {
	return "api_access_tokens"
}