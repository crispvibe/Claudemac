package request

import (
	common "heyu/server/model/shared/request"
	"heyu/server/model/admin"
)

// Register User register structure
type Register struct {
	Username     string `json:"userName" example:"用户名"`
	Password     string `json:"passWord" example:"密码"`
	NickName     string `json:"nickName" example:"昵称"`
	HeaderImg    string `json:"headerImg" example:"头像链接"`
	PrimaryRoleID uint  `json:"primaryRoleId" swaggertype:"string" example:"int 主角色id"`
	Enable       int    `json:"enable" swaggertype:"string" example:"int 是否启用"`
	RoleIds      []uint `json:"roleIds" swaggertype:"string" example:"[]uint 角色id"`
	Phone        string `json:"phone" example:"电话号码"`
	Email        string `json:"email" example:"电子邮箱"`
}

// Login User login structure
type Login struct {
	Username   string `json:"username"`             // 用户名
	Password   string `json:"password"`             // 密码
	SlideToken string `json:"slideToken,omitempty"` // 滑块验证码一次性通行证
}

// ChangePasswordReq Modify password structure
type ChangePasswordReq struct {
	ID          uint   `json:"-"`           // 从 JWT 中提取 user id，避免越权
	Password    string `json:"password"`    // 密码
	NewPassword string `json:"newPassword"` // 新密码
}

type ResetPassword struct {
	ID       uint   `json:"id" form:"id"`
	Password string `json:"password" form:"password" gorm:"comment:用户登录密码"` // 用户登录密码
}

// SetUserPrimaryRole Modify user's primary role structure
type SetUserPrimaryRole struct {
	ID          uint `json:"id"`          // 目标用户ID
	RoleID      uint `json:"roleId"`      // 角色ID
}

// SetUserRoles Modify user's role structure
type SetUserRoles struct {
	ID      uint   `json:"id"`
	RoleIds []uint `json:"roleIds"` // 角色ID
}

type ChangeUserInfo struct {
	ID           uint                  `gorm:"primarykey"`                                                                           // 主键ID
	NickName     string                `json:"nickName" gorm:"comment:用户昵称"`                                                          // 用户昵称
	Phone        string                `json:"phone"  gorm:"comment:用户手机号"`                                                          // 用户手机号
	RoleIds      []uint                `json:"roleIds" gorm:"-"`                                                                     // 角色ID
	Email        string                `json:"email"  gorm:"comment:用户邮箱"`                                                           // 用户邮箱
	HeaderImg    string                `json:"headerImg" gorm:"comment:用户头像"`                                                        // 用户头像
	Enable       int                   `json:"enable" gorm:"comment:冻结用户"`                                                           //冻结用户
	Roles        []admin.Role      `json:"-" gorm:"many2many:account_roles;"`
}

type GetUserList struct {
	common.PageInfo
	Username string `json:"username" form:"username"`
	NickName string `json:"nickName" form:"nickName"`
	Phone    string `json:"phone" form:"phone"`
	Email    string `json:"email" form:"email"`
}
