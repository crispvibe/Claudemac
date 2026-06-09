package admin

import (
	"heyu/server/global"
)

type JwtBlacklist struct {
	global.BaseModel
	Jwt string `gorm:"type:text;comment:jwt"`
}
