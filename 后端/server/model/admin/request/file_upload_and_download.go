package request

import commonReq "heyu/server/model/shared/request"

type FileUploadAndDownloadSearch struct {
	commonReq.PageInfo
	ClassId uint `json:"classId" form:"classId"`
}

type DeleteFileUploadAndDownloadReq struct {
	ID uint `json:"id"`
}

type EditFileNameReq struct {
	ID   uint   `json:"id"`
	Name string `json:"name"`
}

type ImportURLReq struct {
	URL     string `json:"url"`
	Name    string `json:"name"`
	ClassId uint   `json:"classId"`
}
