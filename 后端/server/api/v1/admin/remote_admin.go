package admin

import (
	adminReq "heyu/server/model/admin/request"
	"heyu/server/model/shared/response"

	"github.com/gin-gonic/gin"
)

type RemoteAdminApi struct{}

func (a *RemoteAdminApi) ListUsers(c *gin.Context) {
	var req adminReq.RemoteUserSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListUsers(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) UpdateUserStatus(c *gin.Context) {
	var req adminReq.RemoteStatusUpdate
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.UpdateUserStatus(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("更新成功", c)
}

func (a *RemoteAdminApi) SaveUser(c *gin.Context) {
	var req adminReq.RemoteUserSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveUser(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func (a *RemoteAdminApi) KickUser(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.KickUser(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已踢下线", c)
}

func (a *RemoteAdminApi) BanUser(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.BanUser(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已禁用", c)
}

func (a *RemoteAdminApi) DeleteUser(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteUser(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListDevices(c *gin.Context) {
	var req adminReq.RemoteDeviceSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListDevices(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) UpdateDevice(c *gin.Context) {
	var req adminReq.RemoteDeviceUpdate
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.UpdateDevice(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("更新成功", c)
}

func (a *RemoteAdminApi) KickDevice(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.KickDevice(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已踢下线", c)
}

func (a *RemoteAdminApi) DeleteDevice(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteDevice(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListConnections(c *gin.Context) {
	var req adminReq.RemoteConnectionSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListConnections(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) DeleteConnection(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteConnection(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListCodeAttempts(c *gin.Context) {
	var req adminReq.RemoteCodeAttemptSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListCodeAttempts(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) DeleteCodeAttempt(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteCodeAttempt(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListLegalDocuments(c *gin.Context) {
	var req adminReq.RemoteLegalDocumentSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListLegalDocuments(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) SaveLegalDocument(c *gin.Context) {
	var req adminReq.RemoteLegalDocumentSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveLegalDocument(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func (a *RemoteAdminApi) DeleteLegalDocument(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteLegalDocument(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) GetAppFooter(c *gin.Context) {
	var req adminReq.RemoteAppFooterGet
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.GetAppFooter(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "获取成功", c)
}

func (a *RemoteAdminApi) SaveAppFooter(c *gin.Context) {
	var req adminReq.RemoteAppFooterSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveAppFooter(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func (a *RemoteAdminApi) ListAppUpdates(c *gin.Context) {
	var req adminReq.RemoteAppUpdateSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListAppUpdates(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) SaveAppUpdate(c *gin.Context) {
	var req adminReq.RemoteAppUpdateSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveAppUpdate(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func (a *RemoteAdminApi) DeleteAppUpdate(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteAppUpdate(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListLegalConsents(c *gin.Context) {
	var req adminReq.RemoteLegalConsentSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListLegalConsents(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) DeleteLegalConsent(c *gin.Context) {
	var req adminReq.RemoteAdminIDRequest
	if !bindJSON(c, &req) {
		return
	}
	if err := remoteAdminService.DeleteLegalConsent(req); err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("已删除", c)
}

func (a *RemoteAdminApi) ListSubscriptions(c *gin.Context) {
	var req adminReq.RemoteSubscriptionSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListSubscriptions(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) ListSubscriptionPlans(c *gin.Context) {
	var req adminReq.RemoteSubscriptionPlanSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListSubscriptionPlans(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) ListSubscriptionOrders(c *gin.Context) {
	var req adminReq.RemoteSubscriptionOrderSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListSubscriptionOrders(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) ListAccountDeletions(c *gin.Context) {
	var req adminReq.RemoteAccountDeletionSearch
	if !bindJSON(c, &req) {
		return
	}
	list, total, err := remoteAdminService.ListAccountDeletions(req)
	page(c, list, total, req.Page, req.PageSize, err)
}

func (a *RemoteAdminApi) SaveSubscriptionPlan(c *gin.Context) {
	var req adminReq.RemoteSubscriptionPlanSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveSubscriptionPlan(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func (a *RemoteAdminApi) SaveSubscription(c *gin.Context) {
	var req adminReq.RemoteSubscriptionSave
	if !bindJSON(c, &req) {
		return
	}
	data, err := remoteAdminService.SaveSubscription(req)
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(data, "保存成功", c)
}

func bindJSON(c *gin.Context, value any) bool {
	if err := c.ShouldBindJSON(value); err != nil {
		response.ErrorMessage("参数错误", c)
		return false
	}
	return true
}

func page(c *gin.Context, list any, total int64, pageNum, pageSize int, err error) {
	if err != nil {
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(response.PageResult{List: list, Total: total, Page: pageNum, PageSize: pageSize}, "获取成功", c)
}
