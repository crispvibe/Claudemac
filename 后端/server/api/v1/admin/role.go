package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemRes "heyu/server/model/admin/response"
	"heyu/server/utils"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type RoleApi struct{}

// CreateRole
// @Tags      Role
// @Summary   创建角色
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Role                                                     true  "权限id, 权限名, 父角色id"
// @Success   200   {object}  response.Response{data=systemRes.RoleResponse,msg=string}          "创建角色,返回包括系统角色详情"
// @Router    /roles/create [post]
func (a *RoleApi) CreateRole(c *gin.Context) {
	var role, roleBack admin.Role
	var err error

	if err = c.ShouldBindJSON(&role); err != nil {
		failInvalidParams(c)
		return
	}

	if err = utils.Verify(role, utils.RoleVerify); err != nil {
		failValidation(c)
		return
	}

	if *role.ParentId == 0 && global.AppConfig.System.UseStrictAuth {
		role.ParentId = utils.Pointer(utils.GetUserRoleID(c))
	}

	if roleBack, err = roleService.CreateRole(role); err != nil {
		global.AppLog.Error("创建失败!", zap.Error(err))
		response.ErrorMessage("创建失败", c)
		return
	}
	err = casbinService.FreshCasbin()
	if err != nil {
		global.AppLog.Error("创建成功，权限刷新失败。", zap.Error(err))
		response.ErrorMessage("创建成功，但权限刷新失败", c)
		return
	}
	response.SuccessPayload(systemRes.RoleResponse{Role: roleBack}, "创建成功", c)
}

// CopyRole
// @Tags      Role
// @Summary   拷贝角色
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      response.RoleCopyResponse                                          true  "旧角色id, 新权限id, 新权限名, 新父角色id"
// @Success   200   {object}  response.Response{data=systemRes.RoleResponse,msg=string}          "拷贝角色,返回包括系统角色详情"
// @Router    /roles/copy [post]
func (a *RoleApi) CopyRole(c *gin.Context) {
	var copyInfo systemRes.RoleCopyResponse
	err := c.ShouldBindJSON(&copyInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(copyInfo, utils.OldRoleVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = utils.Verify(copyInfo.Role, utils.RoleVerify)
	if err != nil {
		failValidation(c)
		return
	}
	adminRoleID := utils.GetUserRoleID(c)
	roleBack, err := roleService.CopyRole(adminRoleID, copyInfo)
	if err != nil {
		global.AppLog.Error("拷贝失败!", zap.Error(err))
		response.ErrorMessage("拷贝失败", c)
		return
	}
	response.SuccessPayload(systemRes.RoleResponse{Role: roleBack}, "拷贝成功", c)
}

// DeleteRole
// @Tags      Role
// @Summary   删除角色
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Role                 true  "删除角色"
// @Success   200   {object}  response.Response{msg=string}  "删除角色"
// @Router    /roles/delete [post]
func (a *RoleApi) DeleteRole(c *gin.Context) {
	var role admin.Role
	var err error
	if err = c.ShouldBindJSON(&role); err != nil {
		failInvalidParams(c)
		return
	}
	if err = utils.Verify(role, utils.RoleIdVerify); err != nil {
		failValidation(c)
		return
	}
	// 删除角色之前需要判断是否有用户正在使用此角色
	if err = roleService.DeleteRole(&role); err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	_ = casbinService.FreshCasbin()
	response.SuccessMessage("删除成功", c)
}

// UpdateRole
// @Tags      Role
// @Summary   更新角色信息
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Role                                                     true  "权限id, 权限名, 父角色id"
// @Success   200   {object}  response.Response{data=systemRes.RoleResponse,msg=string}          "更新角色信息,返回包括系统角色详情"
// @Router    /roles/update [put]
func (a *RoleApi) UpdateRole(c *gin.Context) {
	var role admin.Role
	err := c.ShouldBindJSON(&role)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(role, utils.RoleVerify)
	if err != nil {
		failValidation(c)
		return
	}
	roleInfo, err := roleService.UpdateRole(role)
	if err != nil {
		global.AppLog.Error("更新失败!", zap.Error(err))
		response.ErrorMessage("更新失败", c)
		return
	}
	response.SuccessPayload(systemRes.RoleResponse{Role: roleInfo}, "更新成功", c)
}

// GetRoleList
// @Tags      Role
// @Summary   分页获取角色列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.PageInfo                                        true  "页码, 每页大小"
// @Success   200   {object}  response.Response{data=response.PageResult,msg=string}  "分页获取角色列表,返回包括列表,总数,页码,每页数量"
// @Router    /roles/list [post]
func (a *RoleApi) GetRoleList(c *gin.Context) {
	roleID := utils.GetUserRoleID(c)
	list, err := roleService.GetRoleList(roleID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(list, "获取成功", c)
}

// SetRoleDataScope
// @Tags      Role
// @Summary   设置角色资源权限
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.Role                 true  "设置角色资源权限"
// @Success   200   {object}  response.Response{msg=string}  "设置角色资源权限"
// @Router    /roles/data-scope [post]
func (a *RoleApi) SetRoleDataScope(c *gin.Context) {
	var role admin.Role
	err := c.ShouldBindJSON(&role)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(role, utils.RoleIdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	adminRoleID := utils.GetUserRoleID(c)
	err = roleService.SetRoleDataScope(adminRoleID, role)
	if err != nil {
		global.AppLog.Error("设置失败!", zap.Error(err))
		response.ErrorMessage("设置失败", c)
		return
	}
	response.SuccessMessage("设置成功", c)
}
