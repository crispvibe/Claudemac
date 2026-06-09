package admin

import (
	"heyu/server/global"
	"heyu/server/model/shared/response"
	"heyu/server/model/admin"
	systemReq "heyu/server/model/admin/request"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type AttachmentCategoryApi struct{}

func (a *AttachmentCategoryApi) GetCategoryList(c *gin.Context) {
	categories, err := attachmentCategoryService.GetCategoryList()
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessData(categories, c)
}

func (a *AttachmentCategoryApi) AddCategory(c *gin.Context) {
	var category admin.AttachmentCategory
	if err := c.ShouldBindJSON(&category); err != nil {
		failInvalidParams(c)
		return
	}
	if err := attachmentCategoryService.SaveCategory(category); err != nil {
		global.AppLog.Error("操作失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("操作成功", c)
}

func (a *AttachmentCategoryApi) DeleteCategory(c *gin.Context) {
	var req systemReq.DeleteAttachmentCategoryReq
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	if err := attachmentCategoryService.DeleteCategory(req.ID); err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("删除成功", c)
}
