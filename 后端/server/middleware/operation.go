package middleware

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"heyu/server/utils"

	"heyu/server/global"
	"heyu/server/model/admin"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

var respPool sync.Pool
var bufferSize = 1024
var sensitiveLogFields = []string{"password", "oldPassword", "newPassword", "confirmPassword", "token", "access_token", "authorization"}

// 响应体中出现的这些字段默认入库前脱敏，避免 operation_logs 成为凭证泄露面
var sensitiveResponseFields = []string{
	"token", "accessToken", "access_token", "refreshToken", "refresh_token",
	"password", "secret", "signingKey", "apiKey", "api_key",
	"captchaId", "captcha",
}

func init() {
	respPool.New = func() interface{} {
		return make([]byte, bufferSize)
	}
}

func sanitizeOperationBody(body []byte) string {
	if len(body) == 0 {
		return ""
	}
	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err == nil {
		for _, field := range sensitiveLogFields {
			if _, ok := payload[field]; ok {
				payload[field] = "[REDACTED]"
			}
		}
		maskedBody, err := json.Marshal(payload)
		if err == nil {
			return string(maskedBody)
		}
	}
	return string(body)
}

// redactSensitive 递归脱敏 JSON 响应中的敏感字段，防止操作日志表泄露凭证
func redactSensitive(v interface{}) {
	switch node := v.(type) {
	case map[string]interface{}:
		for _, field := range sensitiveResponseFields {
			if _, ok := node[field]; ok {
				node[field] = "[REDACTED]"
			}
		}
		for _, child := range node {
			redactSensitive(child)
		}
	case []interface{}:
		for _, child := range node {
			redactSensitive(child)
		}
	}
}

func sanitizeOperationResponse(resp string) string {
	if resp == "" {
		return ""
	}
	if len(resp) > bufferSize {
		return "[超出记录长度]"
	}
	var payload interface{}
	if err := json.Unmarshal([]byte(resp), &payload); err == nil {
		redactSensitive(payload)
		if masked, err := json.Marshal(payload); err == nil {
			return string(masked)
		}
	}
	return resp
}

func OperationRecord() gin.HandlerFunc {
	return func(c *gin.Context) {
		var body []byte
		var userId int
		if c.Request.Method != http.MethodGet {
			var err error
			body, err = io.ReadAll(c.Request.Body)
			if err != nil {
				global.AppLog.Error("read body from request error:", zap.Error(err))
			} else {
				c.Request.Body = io.NopCloser(bytes.NewBuffer(body))
			}
		} else {
			query := c.Request.URL.RawQuery
			query, _ = url.QueryUnescape(query)
			split := strings.Split(query, "&")
			m := make(map[string]string)
			for _, v := range split {
				kv := strings.Split(v, "=")
				if len(kv) == 2 {
					m[kv[0]] = kv[1]
				}
			}
			body, _ = json.Marshal(&m)
		}
		claims, _ := utils.GetClaims(c)
		if claims != nil && claims.BaseClaims.ID != 0 {
			userId = int(claims.BaseClaims.ID)
		}
		record := admin.OperationRecord{
			Ip:     c.ClientIP(),
			Method: c.Request.Method,
			Path:   c.Request.URL.Path,
			Agent:  c.Request.UserAgent(),
			Body:   "",
			UserID: userId,
		}

		// 上传文件时候 中间件日志进行裁断操作
		if strings.Contains(c.GetHeader("Content-Type"), "multipart/form-data") {
			record.Body = "[文件]"
		} else {
			if len(body) > bufferSize {
				record.Body = "[超出记录长度]"
			} else {
				record.Body = sanitizeOperationBody(body)
			}
		}

		writer := responseBodyWriter{
			ResponseWriter: c.Writer,
			body:           &bytes.Buffer{},
		}
		c.Writer = writer
		now := time.Now()

		c.Next()

		latency := time.Since(now)
		record.ErrorMessage = c.Errors.ByType(gin.ErrorTypePrivate).String()
		record.Status = c.Writer.Status()
		record.Latency = latency
		record.Resp = sanitizeOperationResponse(writer.body.String())

		if strings.Contains(c.Writer.Header().Get("Pragma"), "public") ||
			strings.Contains(c.Writer.Header().Get("Expires"), "0") ||
			strings.Contains(c.Writer.Header().Get("Cache-Control"), "must-revalidate, post-check=0, pre-check=0") ||
			strings.Contains(c.Writer.Header().Get("Content-Type"), "application/force-download") ||
			strings.Contains(c.Writer.Header().Get("Content-Type"), "application/octet-stream") ||
			strings.Contains(c.Writer.Header().Get("Content-Type"), "application/vnd.ms-excel") ||
			strings.Contains(c.Writer.Header().Get("Content-Type"), "application/download") ||
			strings.Contains(c.Writer.Header().Get("Content-Disposition"), "attachment") ||
			strings.Contains(c.Writer.Header().Get("Content-Transfer-Encoding"), "binary") {
			if len(record.Resp) > bufferSize {
				// 截断
				record.Body = "超出记录长度"
			}
		}
		if err := global.AppDB.Create(&record).Error; err != nil {
			global.AppLog.Error("create operation record error:", zap.Error(err))
		}
	}
}

type responseBodyWriter struct {
	gin.ResponseWriter
	body *bytes.Buffer
}

func (r responseBodyWriter) Write(b []byte) (int, error) {
	r.body.Write(b)
	return r.ResponseWriter.Write(b)
}
