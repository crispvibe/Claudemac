package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/request"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	systemRes "heyu/server/model/admin/response"
	"heyu/server/utils"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type APICatalogApi struct{}

// CreateApi
// @Tags      APICatalog
// @Summary   创建基础api
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.APICatalogEntry                  true  "api路径, api中文描述, api组, 方法"
// @Success   200   {object}  response.Response{msg=string}  "创建基础api"
// @Router    /api-catalog/createApi [post]
func (s *APICatalogApi) CreateApi(c *gin.Context) {
	var api admin.APICatalogEntry
	err := c.ShouldBindJSON(&api)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(api, utils.ApiVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = apiService.CreateApi(api)
	if err != nil {
		global.AppLog.Error("创建失败!", zap.Error(err))
		response.ErrorMessage("创建失败", c)
		return
	}
	response.SuccessMessage("创建成功", c)
}

// SyncApi
// @Tags      APICatalog
// @Summary   同步API
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200   {object}  response.Response{msg=string}  "同步API"
// @Router    /api-catalog/syncApi [get]
func (s *APICatalogApi) SyncApi(c *gin.Context) {
	newApis, deleteApis, err := apiService.SyncApi()
	if err != nil {
		global.AppLog.Error("同步失败!", zap.Error(err))
		response.ErrorMessage("同步失败", c)
		return
	}
	response.SuccessData(gin.H{
		"newApis":    newApis,
		"deleteApis": deleteApis,
	}, c)
}

// GetApiGroups
// @Tags      APICatalog
// @Summary   获取API分组
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200   {object}  response.Response{msg=string}  "获取API分组"
// @Router    /api-catalog/getApiGroups [get]
func (s *APICatalogApi) GetApiGroups(c *gin.Context) {
	groups, apiGroupMap, err := apiService.GetApiGroups()
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessData(gin.H{
		"groups":      groups,
		"apiGroupMap": apiGroupMap,
	}, c)
}

// EnterSyncApi
// @Tags      APICatalog
// @Summary   确认同步API
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200   {object}  response.Response{msg=string}  "确认同步API"
// @Router    /api-catalog/enterSyncApi [post]
func (s *APICatalogApi) EnterSyncApi(c *gin.Context) {
	var syncApi systemRes.APISyncPayload
	err := c.ShouldBindJSON(&syncApi)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = apiService.EnterSyncApi(syncApi)
	if err != nil {
		global.AppLog.Error("忽略失败!", zap.Error(err))
		response.ErrorMessage("忽略失败", c)
		return
	}
	response.Success(c)
}

// DeleteApi
// @Tags      APICatalog
// @Summary   删除api
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.APICatalogEntry                  true  "ID"
// @Success   200   {object}  response.Response{msg=string}  "删除api"
// @Router    /api-catalog/deleteApi [post]
func (s *APICatalogApi) DeleteApi(c *gin.Context) {
	var api admin.APICatalogEntry
	err := c.ShouldBindJSON(&api)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(api.BaseModel, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = apiService.DeleteApi(api)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

// GetApiList
// @Tags      APICatalog
// @Summary   分页获取API列表
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      systemReq.SearchApiParams                               true  "分页获取API列表"
// @Success   200   {object}  response.Response{data=response.PageResult,msg=string}  "分页获取API列表,返回包括列表,总数,页码,每页数量"
// @Router    /api-catalog/getApiList [post]
func (s *APICatalogApi) GetApiList(c *gin.Context) {
	var pageInfo systemReq.SearchApiParams
	err := c.ShouldBindJSON(&pageInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(pageInfo.PageInfo, utils.PageInfoVerify)
	if err != nil {
		failValidation(c)
		return
	}
	list, total, err := apiService.GetAPIInfoList(pageInfo.APICatalogEntry, pageInfo.PageInfo, pageInfo.OrderKey, pageInfo.Desc)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(response.PageResult{
		List:     list,
		Total:    total,
		Page:     pageInfo.Page,
		PageSize: pageInfo.PageSize,
	}, "获取成功", c)
}

// GetApiById
// @Tags      APICatalog
// @Summary   根据id获取api
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.GetById                                   true  "根据id获取api"
// @Success   200   {object}  response.Response{data=systemRes.APIEntryResponse}  "根据id获取api,返回包括api详情"
// @Router    /api-catalog/getApiById [post]
func (s *APICatalogApi) GetApiById(c *gin.Context) {
	var idInfo request.GetById
	err := c.ShouldBindJSON(&idInfo)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(idInfo, utils.IdVerify)
	if err != nil {
		failValidation(c)
		return
	}
	api, err := apiService.GetApiById(idInfo.ID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(systemRes.APIEntryResponse{Api: api}, "获取成功", c)
}

// UpdateApi
// @Tags      APICatalog
// @Summary   修改基础api
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      admin.APICatalogEntry                  true  "api路径, api中文描述, api组, 方法"
// @Success   200   {object}  response.Response{msg=string}  "修改基础api"
// @Router    /api-catalog/updateApi [post]
func (s *APICatalogApi) UpdateApi(c *gin.Context) {
	var api admin.APICatalogEntry
	err := c.ShouldBindJSON(&api)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = utils.Verify(api, utils.ApiVerify)
	if err != nil {
		failValidation(c)
		return
	}
	err = apiService.UpdateApi(api)
	if err != nil {
		global.AppLog.Error("修改失败!", zap.Error(err))
		response.ErrorMessage("修改失败", c)
		return
	}
	response.SuccessMessage("修改成功", c)
}

// GetAllApis
// @Tags      APICatalog
// @Summary   获取所有的Api 不分页
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Success   200  {object}  response.Response{data=systemRes.APIEntryListResponse,msg=string}  "获取所有的Api 不分页,返回包括api列表"
// @Router    /api-catalog/getAllApis [post]
func (s *APICatalogApi) GetAllApis(c *gin.Context) {
	roleID := utils.GetUserRoleID(c)
	apis, err := apiService.GetAllApis(roleID)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(systemRes.APIEntryListResponse{Apis: apis}, "获取成功", c)
}

// DeleteApisByIds
// @Tags      APICatalog
// @Summary   删除选中Api
// @Security  ApiKeyAuth
// @accept    application/json
// @Produce   application/json
// @Param     data  body      request.IdsReq                 true  "ID"
// @Success   200   {object}  response.Response{msg=string}  "删除选中Api"
// @Router    /api-catalog/deleteApisByIds [delete]
func (s *APICatalogApi) DeleteApisByIds(c *gin.Context) {
	var ids request.IdsReq
	err := c.ShouldBindJSON(&ids)
	if err != nil {
		failInvalidParams(c)
		return
	}
	err = apiService.DeleteApisByIds(ids)
	if err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage("删除失败", c)
		return
	}
	response.SuccessMessage("删除成功", c)
}
