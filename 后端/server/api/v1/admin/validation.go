package admin

import (
	"heyu/server/model/shared/response"

	"github.com/gin-gonic/gin"
)

func failInvalidParams(c *gin.Context) {
	response.ErrorMessage("参数错误", c)
}

func failValidation(c *gin.Context) {
	response.ErrorMessage("参数校验失败", c)
}
