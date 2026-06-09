package admin

import (
	"strconv"

	"heyu/server/global"
	"heyu/server/model/shared/response"
	systemReq "heyu/server/model/admin/request"
	"heyu/server/utils"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type FileUploadAndDownloadApi struct{}

func (f *FileUploadAndDownloadApi) Upload(c *gin.Context) {
	fileHeader, err := c.FormFile("file")
	if err != nil {
		failInvalidParams(c)
		return
	}
	classID, err := parseUintFormValue(c.PostForm("classId"))
	if err != nil {
		failInvalidParams(c)
		return
	}
	file, err := fileUploadAndDownloadService.UploadFile(fileHeader, classID, utils.GetUserID(c), c.Query("noSave") == "1")
	if err != nil {
		global.AppLog.Error("上传失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(gin.H{"file": file}, "上传成功", c)
}

func (f *FileUploadAndDownloadApi) GetFileList(c *gin.Context) {
	var search systemReq.FileUploadAndDownloadSearch
	if err := c.ShouldBindJSON(&search); err != nil {
		failInvalidParams(c)
		return
	}
	list, total, err := fileUploadAndDownloadService.GetFileList(search)
	if err != nil {
		global.AppLog.Error("获取失败!", zap.Error(err))
		response.ErrorMessage("获取失败", c)
		return
	}
	response.SuccessPayload(response.PageResult{List: list, Total: total, Page: search.Page, PageSize: search.PageSize}, "获取成功", c)
}

func (f *FileUploadAndDownloadApi) DeleteFile(c *gin.Context) {
	var req systemReq.DeleteFileUploadAndDownloadReq
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	if err := fileUploadAndDownloadService.DeleteFile(req.ID); err != nil {
		global.AppLog.Error("删除失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("删除成功", c)
}

func (f *FileUploadAndDownloadApi) EditFileName(c *gin.Context) {
	var req systemReq.EditFileNameReq
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	if err := fileUploadAndDownloadService.EditFileName(req.ID, req.Name); err != nil {
		global.AppLog.Error("编辑失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessMessage("编辑成功", c)
}

func (f *FileUploadAndDownloadApi) ImportURL(c *gin.Context) {
	var req systemReq.ImportURLReq
	if err := c.ShouldBindJSON(&req); err != nil {
		failInvalidParams(c)
		return
	}
	file, err := fileUploadAndDownloadService.ImportURL(req, utils.GetUserID(c))
	if err != nil {
		global.AppLog.Error("导入失败!", zap.Error(err))
		response.ErrorMessage(err.Error(), c)
		return
	}
	response.SuccessPayload(gin.H{"file": file}, "导入成功", c)
}

func parseUintFormValue(value string) (uint, error) {
	if value == "" {
		return 0, nil
	}
	parsed, err := strconv.ParseUint(value, 10, 64)
	if err != nil {
		return 0, err
	}
	return uint(parsed), nil
}
