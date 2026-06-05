package biz

import (
	"strings"

	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
)

const maxRemoteAuditFieldLength = 191

// RecordRemoteAudit writes a best-effort sanitized remote audit event.
// It intentionally stores only identifiers, status, hashed IP, user-agent, and a short message.
func RecordRemoteAudit(userID, deviceID, connectionID *uint, action, status, message, clientIP, userAgent string) {
	if global.AppDB == nil {
		return
	}
	action = truncateRemoteAuditValue(strings.TrimSpace(action))
	if action == "" {
		return
	}
	status = truncateRemoteAuditValue(strings.TrimSpace(status))
	message = truncateRemoteAuditValue(strings.TrimSpace(message))
	ua := truncateRemoteAuditValue(strings.TrimSpace(userAgent))
	ipHash := ""
	if strings.TrimSpace(clientIP) != "" {
		ipHash = hashString(clientIP)
	}
	_ = global.AppDB.Create(&modelBiz.RemoteAuditLog{
		UserID:       userID,
		DeviceID:     deviceID,
		ConnectionID: connectionID,
		Action:       action,
		Status:       status,
		Message:      message,
		IPHash:       ipHash,
		UserAgent:    ua,
	}).Error
}

func truncateRemoteAuditValue(value string) string {
	if len(value) <= maxRemoteAuditFieldLength {
		return value
	}
	return value[:maxRemoteAuditFieldLength]
}
