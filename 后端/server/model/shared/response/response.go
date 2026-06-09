package response

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Response struct {
	Code int         `json:"code"`
	Data interface{} `json:"data"`
	Msg  string      `json:"msg"`
}

const (
	ERROR   = 1
	SUCCESS = 0
)

func Send(code int, data interface{}, msg string, c *gin.Context) {
	c.JSON(http.StatusOK, Response{
		code,
		data,
		msg,
	})
}

func Result(code int, data interface{}, msg string, c *gin.Context) {
	Send(code, data, msg, c)
}

func Success(c *gin.Context) {
	Send(SUCCESS, map[string]interface{}{}, "操作成功", c)
}

func SuccessMessage(message string, c *gin.Context) {
	Send(SUCCESS, map[string]interface{}{}, message, c)
}

func SuccessData(data interface{}, c *gin.Context) {
	Send(SUCCESS, data, "成功", c)
}

func SuccessPayload(data interface{}, message string, c *gin.Context) {
	Send(SUCCESS, data, message, c)
}

func Error(c *gin.Context) {
	Send(ERROR, map[string]interface{}{}, "操作失败", c)
}

func ErrorMessage(message string, c *gin.Context) {
	Send(ERROR, map[string]interface{}{}, message, c)
}

func Unauthorized(message string, c *gin.Context) {
	c.JSON(http.StatusUnauthorized, Response{
		ERROR,
		nil,
		message,
	})
}

func Ok(c *gin.Context) {
	Success(c)
}

func OkWithMessage(message string, c *gin.Context) {
	SuccessMessage(message, c)
}

func OkWithData(data interface{}, c *gin.Context) {
	SuccessData(data, c)
}

func OkWithDetailed(data interface{}, message string, c *gin.Context) {
	SuccessPayload(data, message, c)
}

func Fail(c *gin.Context) {
	Error(c)
}

func FailWithMessage(message string, c *gin.Context) {
	ErrorMessage(message, c)
}

func NoAuth(message string, c *gin.Context) {
	Unauthorized(message, c)
}

func FailWithDetailed(data interface{}, message string, c *gin.Context) {
	Result(ERROR, data, message, c)
}
