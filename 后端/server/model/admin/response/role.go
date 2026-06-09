package response

import "heyu/server/model/admin"

type RoleResponse struct {
	Role admin.Role `json:"role"`
}

type RoleCopyResponse struct {
	Role      admin.Role `json:"role"`
	OldRoleID uint                `json:"oldRoleId"` // 旧角色ID
}
