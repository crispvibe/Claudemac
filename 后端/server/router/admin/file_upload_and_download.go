package admin

import (
	"heyu/server/middleware"
	"github.com/gin-gonic/gin"
)

type FileUploadAndDownloadRouter struct{}

func (f *FileUploadAndDownloadRouter) InitFileUploadAndDownloadRouter(Router *gin.RouterGroup) {
	fileUploadAndDownloadRouter := Router.Group("attachments").Use(middleware.OperationRecord())
	fileUploadAndDownloadRouterWithoutRecord := Router.Group("attachments")
	{
		fileUploadAndDownloadRouter.POST("upload", fileUploadAndDownloadApi.Upload)
		fileUploadAndDownloadRouter.POST("deleteFile", fileUploadAndDownloadApi.DeleteFile)
		fileUploadAndDownloadRouter.POST("editFileName", fileUploadAndDownloadApi.EditFileName)
		fileUploadAndDownloadRouter.POST("importURL", fileUploadAndDownloadApi.ImportURL)
	}
	{
		fileUploadAndDownloadRouterWithoutRecord.POST("getFileList", fileUploadAndDownloadApi.GetFileList)
	}
}
