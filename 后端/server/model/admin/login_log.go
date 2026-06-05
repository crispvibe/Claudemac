package admin

import (
	"heyu/server/global"
)

type LoginLog struct {
	global.BaseModel
	Username      string  `json:"username" gorm:"column:username;comment:用户名"`
	Ip            string  `json:"ip" gorm:"column:ip;comment:请求ip"`
	Status        bool    `json:"status" gorm:"column:status;comment:登录状态"`
	ErrorMessage  string  `json:"errorMessage" gorm:"column:error_message;comment:错误信息"`
	Agent         string  `json:"agent" gorm:"column:agent;comment:代理"`
	UserID        uint    `json:"userId" gorm:"column:user_id;comment:用户id"`
	User          Account `json:"user" gorm:"foreignKey:UserID"`
}

func (LoginLog) TableName() string {
	return "login_logs"
}