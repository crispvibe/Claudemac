package biz

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"time"

	"go.uber.org/zap"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizRes "heyu/server/model/biz/response"
)

func (s *RemoteService) GetICEServers(userID, connectionID uint) (bizRes.RemoteICEServerResponse, error) {
	var conn modelBiz.RemoteConnectionAttempt
	if err := global.AppDB.Where("id = ? AND status = ? AND (from_user_id = ? OR to_user_id = ?)", connectionID, remoteConnectionAccepted, userID, userID).First(&conn).Error; err != nil {
		return bizRes.RemoteICEServerResponse{}, errors.New("连接不存在或未授权")
	}

	servers := make([]bizRes.RemoteICEServer, 0, 2)
	stunURLs := sanitizedURLs(global.AppConfig.Remote.StunURLs, "stun")
	if len(stunURLs) > 0 {
		servers = append(servers, bizRes.RemoteICEServer{URLs: stunURLs})
	}

	turnURLs := sanitizedURLs(global.AppConfig.Remote.TurnURLs, "turn", "turns")
	turnConfigured := strings.TrimSpace(global.AppConfig.Remote.TurnSecret) != "" && len(turnURLs) > 0
	hasTurn := false
	if turnConfigured {
		username, credential := turnRESTCredentials(userID, conn.ID, global.AppConfig.Remote.TurnSecret, global.AppConfig.Remote.TurnCredentialTTL)
		servers = append(servers, bizRes.RemoteICEServer{
			URLs:       turnURLs,
			Username:   username,
			Credential: credential,
			Realm:      strings.TrimSpace(global.AppConfig.Remote.TurnRealm),
		})
		hasTurn = true
	}
	remoteAppLog().Info(
		"remote ice servers issued",
		zap.Uint("userID", userID),
		zap.Uint("connectionID", conn.ID),
		zap.Strings("stunURLs", stunURLs),
		zap.Strings("turnURLs", turnURLs),
		zap.Bool("turnConfigured", turnConfigured),
		zap.Bool("hasTurn", hasTurn),
		zap.Int("serverCount", len(servers)),
	)

	return bizRes.RemoteICEServerResponse{ICEServers: servers}, nil
}

func turnRESTCredentials(userID, connectionID uint, secret string, ttlSeconds int) (string, string) {
	if ttlSeconds <= 0 {
		ttlSeconds = 600
	}
	expiresAt := time.Now().Add(time.Duration(ttlSeconds) * time.Second).Unix()
	username := fmt.Sprintf("%d:%d:%d", expiresAt, userID, connectionID)
	mac := hmac.New(sha1.New, []byte(strings.TrimSpace(secret)))
	_, _ = mac.Write([]byte(username))
	return username, base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

func sanitizedURLs(urls []string, allowedSchemes ...string) []string {
	allowed := make(map[string]struct{}, len(allowedSchemes))
	for _, scheme := range allowedSchemes {
		allowed[strings.ToLower(strings.TrimSpace(scheme))] = struct{}{}
	}
	cleaned := make([]string, 0, len(urls))
	for _, rawURL := range urls {
		rawURL = strings.TrimSpace(rawURL)
		if rawURL == "" {
			continue
		}
		scheme, rest, ok := strings.Cut(rawURL, ":")
		scheme = strings.ToLower(strings.TrimSpace(scheme))
		if !ok || rest == "" {
			remoteAppLog().Warn("remote ice url skipped", zap.String("url", rawURL), zap.String("reason", "missing_scheme_or_host"))
			continue
		}
		if _, exists := allowed[scheme]; !exists {
			remoteAppLog().Warn("remote ice url skipped", zap.String("url", rawURL), zap.String("scheme", scheme), zap.String("reason", "unsupported_scheme"))
			continue
		}
		if (scheme == "turn" || scheme == "turns") && strings.Contains(rawURL, "?") {
			query := strings.ToLower(rawURL[strings.Index(rawURL, "?")+1:])
			if strings.Contains(query, "transport=") && !strings.Contains(query, "transport=udp") && !strings.Contains(query, "transport=tcp") {
				remoteAppLog().Warn("remote ice url skipped", zap.String("url", rawURL), zap.String("reason", "unsupported_transport"))
				continue
			}
		}
		cleaned = append(cleaned, rawURL)
	}
	return cleaned
}
