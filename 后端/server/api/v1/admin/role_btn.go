package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin/request"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type RoleButtonBindingApi struct{}

// GetRoleButtonBindings
// @Tags      RoleButtonBinding
// @Summary   获取权限按钮
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.RoleButtonBindingRequest                                          true  "菜单id, 角色id, 选中的按钮id"
// @Success   200   {object}  response.Response{data=response.RoleButtonBindingResponse,msg=string}     "返回列表成功"
// @Router    /role-buttons/bindings [post]
func (a *RoleButtonBindingApi) GetRoleButtonBindings(c *gin.Context) {
	var req request.RoleButtonBindingRequest
	err := c.ShouldBindJSON(&req)
	if err != nil {
		failInvalidParams(c)
		return
	}
	res, err := roleButtonBindingService.GetRoleButtonBindings(req)
	if err != nil {
		global.AppLog.Error("查询失败!", zap.Error(err))
		response.ErrorMessage("查询失败", c)
		return
	}
	response.SuccessPayload(res, "查询成功", c)
}

// UpdateRoleButtonBindings
// @Tags      RoleButtonBinding
// @Summary   设置权限按钮
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.RoleButtonBindingRequest     true  "菜单id, 角色id, 选中的按钮id"
// @Success   200   {object}  response.Response{msg=string}  "返回列表成功"
// @Router    /role-buttons/bindings/update [post]
func (a *RoleButtonBindingApi) UpdateRoleButtonBindings(c *gin.Context) {
	var req request.RoleButtonBindingRequest
	err := c.ShouldBindJSON(&req)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = roleButtonBindingService.UpdateRoleButtonBindings(req)
	if err != nil {
		global.AppLog.Error("分配失败!", zap.Error(err))
		response.ErrorMessage("分配失败", c)
		return
	}
	response.SuccessMessage("分配成功", c)
}

// CanRemoveRoleButtonBinding
// @Tags      RoleButtonBinding
// @Summary   设置权限按钮
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200  {object}  response.Response{msg=string}  "删除成功"
// @Router    /role-buttons/bindings/removal-check [post]
func (a *RoleButtonBindingApi) CanRemoveRoleButtonBinding(c *gin.Context) {
	id := c.Query("id")
	err := roleButtonBindingService.CanRemoveRoleButtonBinding(id)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}
