package utils

import (
	"errors"
	"time"

	jwt "github.com/golang-jwt/jwt/v5"
	"heyu/server/global"
)

type RemoteClaims struct {
	UserID       uint   `json:"userId"`
	Phone        string `json:"phone"`
	Email        string `json:"email"`
	Scope        string `json:"scope"`
	TokenVersion int    `json:"tokenVersion"`
	jwt.RegisteredClaims
}

func CreateRemoteAccessToken(userID uint, phone, email string, tokenVersion int) (string, *RemoteClaims, error) {
	expiresAt := time.Now().Add(2 * time.Hour)
	claims := &RemoteClaims{
		UserID:       userID,
		Phone:        phone,
		Email:        email,
		Scope:        "remote",
		TokenVersion: tokenVersion,
		RegisteredClaims: jwt.RegisteredClaims{
			Audience:  jwt.ClaimStrings{"remote"},
			NotBefore: jwt.NewNumericDate(time.Now().Add(-time.Second)),
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			Issuer:    global.AppConfig.JWT.Issuer,
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString([]byte(global.AppConfig.JWT.SigningKey))
	return signed, claims, err
}

func ParseRemoteAccessToken(tokenString string) (*RemoteClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &RemoteClaims{}, func(token *jwt.Token) (interface{}, error) {
		return []byte(global.AppConfig.JWT.SigningKey), nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*RemoteClaims)
	if !ok || !token.Valid || claims.Scope != "remote" || claims.UserID == 0 {
		return nil, errors.New("invalid remote token")
	}
	return claims, nil
}
