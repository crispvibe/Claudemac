package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type CasbinApi struct{}

// UpdateCasbin
// @Tags      Casbin
// @Summary   更新角色api权限
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.CasbinInReceive        true  "权限id, 权限模型列表"
// @Success   200   {object}  response.Response{msg=string}  "更新角色api权限"
// @Router    /role-policies/update [post]
func (cas *CasbinApi) UpdateCasbin(c *gin.Context) {
	var cmr request.CasbinInReceive
	err := c.ShouldBindJSON(&cmr)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(cmr, utils.RoleIdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	adminRoleID := utils.GetUserRoleID(c)
	err = casbinService.UpdateCasbin(adminRoleID, cmr.RoleID, cmr.CasbinInfos)
	if err != nil {
		global.AppLog.Error("更新失败!", zap.Error(err))
		response.ErrorMessage("更新失败", c)
		return
	}
	response.SuccessMessage("更新成功", c)
}

// GetPolicyPathByRoleID
// @Tags      Casbin
// @Summary   获取权限列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.CasbinInReceive                                          true  "权限id, 权限模型列表"
// @Success   200   {object}  response.Response{data=systemRes.PolicyPathResponse,msg=string}  "获取权限列表,返回包括casbin详情列表"
// @Router    /role-policies/by-role [post]
func (cas *CasbinApi) GetPolicyPathByRoleID(c *gin.Context) {
	var casbin request.CasbinInReceive
	err := c.ShouldBindJSON(&casbin)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(casbin, utils.RoleIdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	paths := casbinService.GetPolicyPathByRoleID(casbin.RoleID)
	response.SuccessPayload(systemRes.PolicyPathResponse{Paths: paths}, "获取成功", c)
}
