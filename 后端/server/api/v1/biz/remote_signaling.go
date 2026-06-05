package biz

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
)

func (a *RemoteApi) SignalingWebSocket(c *gin.Context) {
	token := strings.TrimSpace(c.Query("token"))
	if token == "" {
		c.String(http.StatusUnauthorized, "missing token")
		return
	}
	remoteSignalingService.HandleWebSocket(c.Writer, c.Request, token)
}
