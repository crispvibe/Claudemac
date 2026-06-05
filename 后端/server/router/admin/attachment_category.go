package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type AttachmentCategoryRouter struct{}

func (a *AttachmentCategoryRouter) InitAttachmentCategoryRouter(Router *gin.RouterGroup) {
	attachmentCategoryRouter := Router.Group("attachment-categories").Use(middleware.OperationRecord())
	attachmentCategoryRouterWithoutRecord := Router.Group("attachment-categories")
	{
		attachmentCategoryRouter.POST("addCategory", attachmentCategoryApi.AddCategory)
		attachmentCategoryRouter.POST("deleteCategory", attachmentCategoryApi.DeleteCategory)
	}
	{
		attachmentCategoryRouterWithoutRecord.GET("getCategoryList", attachmentCategoryApi.GetCategoryList)
	}
}
