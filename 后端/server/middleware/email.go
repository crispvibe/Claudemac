package middleware

import (
	"github.com/gin-gonic/gin"
)

func ErrorToEmail() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()
	}
}
