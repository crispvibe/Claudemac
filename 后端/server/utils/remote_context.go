package utils

import "github.com/gin-gonic/gin"

func GetRemoteClaims(c *gin.Context) *RemoteClaims {
	claims, ok := c.Get("remoteClaims")
	if !ok {
		return nil
	}
	remoteClaims, ok := claims.(*RemoteClaims)
	if !ok {
		return nil
	}
	return remoteClaims
}

func GetRemoteUserID(c *gin.Context) uint {
	claims := GetRemoteClaims(c)
	if claims == nil {
		return 0
	}
	return claims.UserID
}
