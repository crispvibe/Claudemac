package response

import (
	"heyu/server/model/admin"
)

type UserProfileResponse struct {
	User admin.Account `json:"user"`
}
type LoginResponse struct {
	User      admin.Account `json:"user"`
	ExpiresAt int64          `json:"expiresAt"`
}
