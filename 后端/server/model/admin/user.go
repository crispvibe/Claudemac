package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared"
	"github.com/google/uuid"
)

type Login interface {
	GetUsername() string
	GetNickname() string
	GetUUID() uuid.UUID
	GetUserId() uint
	GetRoleID() uint
	GetUserInfo() any
}

var _ Login = new(Account)

type Account struct {
	global.BaseModel
	UUID          uuid.UUID      `json:"uuid" gorm:"index;comment:用户UUID"`                                                                   // 用户UUID
	Username      string         `json:"userName" gorm:"index;comment:用户登录名"`                                                                // 用户登录名
	Password      string         `json:"-"  gorm:"comment:用户登录密码"`                                                                           // 用户登录密码
	NickName      string         `json:"nickName" gorm:"comment:用户昵称"`                                                                        // 用户昵称
	HeaderImg     string         `json:"headerImg" gorm:"comment:用户头像"`                                                                       // 用户头像
	PrimaryRoleID uint           `json:"primaryRoleId" gorm:"column:primary_role_id;comment:用户角色ID"`                                         // 用户角色ID
	PrimaryRole   Role           `json:"primaryRole" gorm:"foreignKey:PrimaryRoleID;references:RoleID;comment:用户角色"`                        // 用户角色
	Roles         []Role         `json:"roles" gorm:"many2many:account_roles;foreignKey:ID;joinForeignKey:AccountID;references:RoleID;joinReferences:RoleID"` // 多用户角色
	Phone         string         `json:"phone"  gorm:"comment:用户手机号"`                                                                        // 用户手机号
	Email         string         `json:"email"  gorm:"comment:用户邮箱"`                                                                         // 用户邮箱
	Enable        int            `json:"enable" gorm:"default:1;comment:用户是否被冻结 1正常 2冻结"`                                                    //用户是否被冻结 1正常 2冻结
	OriginSetting shared.JSONMap `json:"originSetting" form:"originSetting" gorm:"type:text;default:null;column:origin_setting;comment:配置;"` //配置
}

func (Account) TableName() string {
	return "accounts"
}

func (s *Account) GetUsername() string {
	return s.Username
}

func (s *Account) GetNickname() string {
	return s.NickName
}

func (s *Account) GetUUID() uuid.UUID {
	return s.UUID
}

func (s *Account) GetUserId() uint {
	return s.ID
}

func (s *Account) GetRoleID() uint {
	return s.PrimaryRoleID
}

func (s *Account) GetUserInfo() any {
	return *s
}