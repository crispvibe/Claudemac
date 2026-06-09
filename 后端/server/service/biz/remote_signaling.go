package biz

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	gorilla "github.com/gorilla/websocket"
	"go.uber.org/zap"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
	bizRes "heyu/server/model/biz/response"
	"heyu/server/utils"
)

type RemoteSignalingService struct {
	connections sync.Map // deviceId(uint) -> *remoteSignalingConn
	tunnels     sync.Map // connectionId(uint) -> *remoteTunnelSession
}

const (
	maxRemoteSignalingPayloadBytes = 64 * 1024
	maxRemoteTunnelFrameBytes      = 12 * 1024 * 1024
	maxRemoteSignalingMessageBytes = maxRemoteTunnelFrameBytes + maxRemoteSignalingPayloadBytes
	remoteSignalingWriteWait       = 10 * time.Second
	remoteSignalingPongWait        = 75 * time.Second
	remoteSignalingPingPeriod      = 25 * time.Second
)

type remoteSignalingConn struct {
	userID     uint
	deviceID   uint
	ws         *gorilla.Conn
	mu         sync.Mutex
	lastPongMu sync.RWMutex
	lastPong   time.Time
	closed     chan struct{}
	closeOnce  sync.Once
}

type remoteSignalingEnvelope struct {
	Type         string          `json:"type"`
	DeviceID     uint            `json:"deviceId,omitempty"`
	FromDeviceID uint            `json:"fromDeviceId,omitempty"`
	ToDeviceID   uint            `json:"toDeviceId,omitempty"`
	ConnectionID uint            `json:"connectionId,omitempty"`
	Status       string          `json:"status,omitempty"`
	Reason       string          `json:"reason,omitempty"`
	Payload      json.RawMessage `json:"payload,omitempty"`
	Frame        string          `json:"frame,omitempty"`
	Seq          uint64          `json:"seq,omitempty"`
	Code         string          `json:"code,omitempty"`
	Connection   any             `json:"connection,omitempty"`
	Device       any             `json:"device,omitempty"`
	Online       *bool           `json:"online,omitempty"`
	Message      string          `json:"message,omitempty"`
}

type remoteTunnelSession struct {
	connectionID uint
	fromDeviceID uint
	toDeviceID   uint
	createdAt    time.Time
	lastMu       sync.Mutex
	lastActivity time.Time
}

func (s *RemoteSignalingService) HandleWebSocket(w http.ResponseWriter, r *http.Request, tokenString string) {
	claims, err := utils.ParseRemoteAccessToken(tokenString)
	if err != nil {
		http.Error(w, "登录状态已失效，请重新登录。", http.StatusUnauthorized)
		return
	}
	var user modelBiz.RemoteUser
	if err := global.AppDB.Select("id", "status", "token_version").First(&user, claims.UserID).Error; err != nil || user.Status != remoteStatusActive || user.TokenVersion != claims.TokenVersion {
		http.Error(w, "登录状态已失效，请重新登录。", http.StatusUnauthorized)
		return
	}

	upgrader := gorilla.Upgrader{
		ReadBufferSize:  4096,
		WriteBufferSize: 4096,
		CheckOrigin: func(*http.Request) bool {
			return true
		},
	}
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		remoteAppLog().Warn("remote signaling upgrade failed", zap.Uint("userID", claims.UserID), zap.Error(err))
		return
	}
	s.handleSocket(ws, claims.UserID)
}

func (s *RemoteSignalingService) IsDeviceOnline(deviceID uint) bool {
	_, ok := s.connections.Load(deviceID)
	return ok
}

func (s *RemoteSignalingService) KickDevice(deviceID uint) {
	value, ok := s.connections.Load(deviceID)
	if !ok {
		return
	}
	if conn, ok := value.(*remoteSignalingConn); ok {
		_ = conn.send(remoteSignalingEnvelope{Type: "error", DeviceID: deviceID, Message: "这台设备已被管理员下线，请重新登录。"})
		conn.close()
	}
}

func (s *RemoteSignalingService) KickUser(userID uint) {
	s.connections.Range(func(_, value any) bool {
		conn, ok := value.(*remoteSignalingConn)
		if ok && conn.userID == userID {
			_ = conn.send(remoteSignalingEnvelope{Type: "error", Message: "登录状态已失效，请重新登录。"})
			conn.close()
		}
		return true
	})
}

func (s *RemoteSignalingService) PushPendingConnect(conn modelBiz.RemoteConnectionAttempt) {
	message := remoteSignalingEnvelope{Type: "pending_connect", ConnectionID: conn.ID, FromDeviceID: derefUint(conn.FromDeviceID), ToDeviceID: conn.ToDeviceID, Status: conn.Status, Reason: conn.Reason, Connection: bizRes.RemoteConnectionFromModel(conn)}
	s.sendToDevice(conn.ToDeviceID, message)
}

func (s *RemoteSignalingService) PushConnectDecision(conn modelBiz.RemoteConnectionAttempt) {
	s.PushConnectDecisionResponse(conn, bizRes.RemoteConnectionFromModel(conn))
}

func (s *RemoteSignalingService) PushConnectDecisionResponse(conn modelBiz.RemoteConnectionAttempt, connection bizRes.RemoteConnectionResponse) {
	message := remoteSignalingEnvelope{Type: "connect_decision", ConnectionID: conn.ID, FromDeviceID: derefUint(conn.FromDeviceID), ToDeviceID: conn.ToDeviceID, Status: connection.Status, Reason: connection.Reason, Connection: connection}
	if conn.FromDeviceID != nil {
		s.sendToDevice(*conn.FromDeviceID, message)
	}
	if conn.ToDeviceID != 0 {
		s.sendToDevice(conn.ToDeviceID, message)
	}
}

func (s *RemoteSignalingService) BroadcastPresence(deviceID uint, online bool) {
	var device modelBiz.RemoteDevice
	if err := global.AppDB.Select("id", "user_id").First(&device, deviceID).Error; err != nil || device.UserID == 0 {
		return
	}
	message := remoteSignalingEnvelope{Type: "presence_update", DeviceID: deviceID, Online: &online}
	s.connections.Range(func(_, value any) bool {
		if conn, ok := value.(*remoteSignalingConn); ok && conn.deviceID != deviceID && conn.userID == device.UserID {
			_ = conn.send(message)
		}
		return true
	})
}

func (s *RemoteSignalingService) handleSocket(ws *gorilla.Conn, userID uint) {
	ws.SetReadLimit(maxRemoteSignalingMessageBytes)
	_ = ws.SetReadDeadline(time.Now().Add(remoteSignalingPongWait))

	var hello remoteSignalingEnvelope
	if err := ws.ReadJSON(&hello); err != nil || hello.Type != "hello" || hello.DeviceID == 0 {
		remoteAppLog().Warn("remote signaling hello failed", zap.Uint("userID", userID), zap.Error(err))
		_ = writeRemoteSignalingJSON(ws, remoteSignalingEnvelope{Type: "error", Message: "设备连接初始化失败，请重新打开 App。"})
		_ = ws.Close()
		return
	}
	device, err := s.verifyDevice(userID, hello.DeviceID)
	if err != nil {
		remoteAppLog().Warn("remote signaling device verify failed", zap.Uint("userID", userID), zap.Uint("deviceID", hello.DeviceID), zap.Error(err))
		_ = writeRemoteSignalingJSON(ws, remoteSignalingEnvelope{Type: "error", Message: err.Error()})
		_ = ws.Close()
		return
	}

	conn := &remoteSignalingConn{userID: userID, deviceID: device.ID, ws: ws, lastPong: time.Now(), closed: make(chan struct{})}
	ws.SetPongHandler(func(string) error {
		conn.setLastPong(time.Now())
		return ws.SetReadDeadline(time.Now().Add(remoteSignalingPongWait))
	})
	if existing, loaded := s.connections.Swap(device.ID, conn); loaded {
		if old, ok := existing.(*remoteSignalingConn); ok {
			old.close()
		}
	}
	remoteAppLog().Info("remote signaling connected", zap.Uint("userID", userID), zap.Uint("deviceID", device.ID), zap.String("deviceType", device.DeviceType))
	defer func() {
		s.connections.CompareAndDelete(device.ID, conn)
		s.closeTunnelsForConn(conn, "socket_disconnect")
		conn.close()
		now := time.Now()
		_ = global.AppDB.Model(&device).Updates(map[string]any{"last_seen_at": now, "updated_at": now}).Error
		s.BroadcastPresence(device.ID, false)
		remoteAppLog().Info("remote signaling disconnected", zap.Uint("userID", userID), zap.Uint("deviceID", device.ID), zap.String("deviceType", device.DeviceType))
	}()

	now := time.Now()
	_ = global.AppDB.Model(&device).Updates(map[string]any{"last_seen_at": now, "updated_at": now}).Error
	_ = conn.send(remoteSignalingEnvelope{Type: "hello_ack", DeviceID: device.ID})
	s.BroadcastPresence(device.ID, true)
	go s.heartbeat(conn)

	for {
		var incoming remoteSignalingEnvelope
		if err := ws.ReadJSON(&incoming); err != nil {
			remoteAppLog().Warn("remote signaling receive failed", zap.Uint("userID", userID), zap.Uint("deviceID", device.ID), zap.Error(err))
			return
		}
		_ = ws.SetReadDeadline(time.Now().Add(remoteSignalingPongWait))
		s.handleMessage(conn, incoming)
	}
}

func (s *RemoteSignalingService) heartbeat(conn *remoteSignalingConn) {
	ticker := time.NewTicker(remoteSignalingPingPeriod)
	defer ticker.Stop()
	for {
		select {
		case <-conn.closed:
			return
		case <-ticker.C:
			if time.Since(conn.getLastPong()) > remoteSignalingPongWait {
				remoteAppLog().Warn("remote signaling pong timeout", zap.Uint("userID", conn.userID), zap.Uint("deviceID", conn.deviceID))
				conn.close()
				return
			}
			_ = conn.send(remoteSignalingEnvelope{Type: "ping"})
			_ = conn.writeControl(gorilla.PingMessage, []byte("ping"))
		}
	}
}

func (s *RemoteSignalingService) handleMessage(conn *remoteSignalingConn, message remoteSignalingEnvelope) {
	switch message.Type {
	case "ping":
		conn.setLastPong(time.Now())
		_ = conn.send(remoteSignalingEnvelope{Type: "pong"})
	case "pong":
		conn.setLastPong(time.Now())
	case "bye":
		conn.close()
	case "relay":
		if err := s.relay(conn, message); err != nil {
			remoteAppLog().Warn("remote signaling relay failed", zap.Uint("fromDeviceID", conn.deviceID), zap.Uint("toDeviceID", message.ToDeviceID), zap.Uint("connectionID", message.ConnectionID), zap.String("payloadKind", signalingPayloadKindForLog(message.Payload)), zap.Error(err))
			_ = conn.send(remoteSignalingEnvelope{Type: "error", ConnectionID: message.ConnectionID, Message: remoteSignalingUserMessage(err)})
		}
	case "tunnel_open":
		if err := s.openTunnel(conn, message); err != nil {
			remoteAppLog().Warn("remote tunnel open failed", zap.Uint("fromDeviceID", conn.deviceID), zap.Uint("connectionID", message.ConnectionID), zap.Error(err))
			_ = conn.send(remoteSignalingEnvelope{Type: "tunnel_error", ConnectionID: message.ConnectionID, Code: strings.TrimSpace(err.Error()), Message: remoteSignalingUserMessage(err)})
		}
	case "tunnel_frame":
		if err := s.forwardTunnelFrame(conn, message); err != nil {
			remoteAppLog().Warn("remote tunnel frame failed", zap.Uint("fromDeviceID", conn.deviceID), zap.Uint("connectionID", message.ConnectionID), zap.Uint64("seq", message.Seq), zap.Int("frameBytes", len(message.Frame)), zap.Error(err))
			_ = conn.send(remoteSignalingEnvelope{Type: "tunnel_error", ConnectionID: message.ConnectionID, Seq: message.Seq, Code: strings.TrimSpace(err.Error()), Message: remoteSignalingUserMessage(err)})
		}
	case "tunnel_close":
		s.closeTunnelFrom(conn, message.ConnectionID, strings.TrimSpace(message.Reason))
	}
}

func (s *RemoteSignalingService) openTunnel(sender *remoteSignalingConn, message remoteSignalingEnvelope) error {
	conn, err := s.verifyTunnelConnection(sender, message.ConnectionID)
	if err != nil {
		return err
	}
	if conn.FromDeviceID == nil || *conn.FromDeviceID != sender.deviceID {
		return errors.New("not_connection_party")
	}
	if conn.ToDeviceID == 0 {
		return errors.New("target_not_connection_party")
	}
	if !s.IsDeviceOnline(conn.ToDeviceID) {
		return errors.New("target_device_offline")
	}
	now := time.Now()
	session := &remoteTunnelSession{connectionID: conn.ID, fromDeviceID: sender.deviceID, toDeviceID: conn.ToDeviceID, createdAt: now, lastActivity: now}
	s.tunnels.Store(conn.ID, session)
	open := remoteSignalingEnvelope{
		Type:         "tunnel_open",
		ConnectionID: conn.ID,
		FromDeviceID: sender.deviceID,
		ToDeviceID:   conn.ToDeviceID,
		Status:       conn.Status,
		Reason:       conn.Reason,
		Connection:   bizRes.RemoteConnectionFromModel(conn),
	}
	if !s.sendToDevice(conn.ToDeviceID, open) {
		s.tunnels.Delete(conn.ID)
		return errors.New("target_device_offline")
	}
	_ = sender.send(remoteSignalingEnvelope{Type: "tunnel_open_ack", ConnectionID: conn.ID, FromDeviceID: conn.ToDeviceID, ToDeviceID: sender.deviceID, Status: conn.Status})
	remoteAppLog().Info("remote tunnel opened", zap.Uint("connectionID", conn.ID), zap.Uint("fromDeviceID", sender.deviceID), zap.Uint("toDeviceID", conn.ToDeviceID))
	return nil
}

func (s *RemoteSignalingService) forwardTunnelFrame(sender *remoteSignalingConn, message remoteSignalingEnvelope) error {
	if message.ConnectionID == 0 {
		return errors.New("invalid_tunnel_payload")
	}
	if message.Frame == "" {
		return errors.New("invalid_tunnel_payload")
	}
	if len(message.Frame) > maxRemoteTunnelFrameBytes {
		s.closeTunnel(message.ConnectionID, sender.deviceID, "frame_too_large")
		return errors.New("frame_too_large")
	}
	value, ok := s.tunnels.Load(message.ConnectionID)
	if !ok {
		return errors.New("tunnel_not_open")
	}
	session, ok := value.(*remoteTunnelSession)
	if !ok {
		return errors.New("tunnel_not_open")
	}
	targetDeviceID := uint(0)
	if sender.deviceID == session.fromDeviceID {
		targetDeviceID = session.toDeviceID
	} else if sender.deviceID == session.toDeviceID {
		targetDeviceID = session.fromDeviceID
	} else {
		return errors.New("not_connection_party")
	}
	session.touch(time.Now())
	out := remoteSignalingEnvelope{Type: "tunnel_frame", ConnectionID: session.connectionID, FromDeviceID: sender.deviceID, ToDeviceID: targetDeviceID, Status: remoteConnectionAccepted, Seq: message.Seq, Frame: message.Frame}
	if !s.sendToDevice(targetDeviceID, out) {
		s.closeTunnel(session.connectionID, sender.deviceID, "target_device_offline")
		return errors.New("target_device_offline")
	}
	return nil
}

func (s *RemoteSignalingService) verifyTunnelConnection(sender *remoteSignalingConn, connectionID uint) (modelBiz.RemoteConnectionAttempt, error) {
	if connectionID == 0 {
		return modelBiz.RemoteConnectionAttempt{}, errors.New("invalid_tunnel_payload")
	}
	var conn modelBiz.RemoteConnectionAttempt
	if err := global.AppDB.Where("id = ?", connectionID).First(&conn).Error; err != nil {
		return modelBiz.RemoteConnectionAttempt{}, err
	}
	if conn.Status != remoteConnectionAccepted {
		return modelBiz.RemoteConnectionAttempt{}, errors.New("connection_not_ready")
	}
	fromMatches := conn.FromDeviceID != nil && *conn.FromDeviceID == sender.deviceID && conn.FromUserID == sender.userID
	toMatches := conn.ToDeviceID == sender.deviceID && conn.ToUserID == sender.userID
	if !fromMatches && !toMatches {
		return modelBiz.RemoteConnectionAttempt{}, errors.New("not_connection_party")
	}
	return conn, nil
}

func (s *RemoteSignalingService) closeTunnelFrom(sender *remoteSignalingConn, connectionID uint, reason string) {
	if connectionID == 0 {
		return
	}
	s.closeTunnel(connectionID, sender.deviceID, reason)
}

func (s *RemoteSignalingService) closeTunnelsForConn(conn *remoteSignalingConn, reason string) {
	s.tunnels.Range(func(key, value any) bool {
		session, ok := value.(*remoteTunnelSession)
		if !ok {
			return true
		}
		if session.fromDeviceID == conn.deviceID || session.toDeviceID == conn.deviceID {
			if id, ok := key.(uint); ok {
				s.closeTunnel(id, conn.deviceID, reason)
			}
		}
		return true
	})
}

func (s *RemoteSignalingService) closeTunnel(connectionID uint, originDeviceID uint, reason string) {
	value, ok := s.tunnels.Load(connectionID)
	if !ok {
		return
	}
	s.tunnels.Delete(connectionID)
	session, ok := value.(*remoteTunnelSession)
	if !ok {
		return
	}
	if reason == "" {
		reason = "closed"
	}
	if originDeviceID != session.fromDeviceID {
		_ = s.sendToDevice(session.fromDeviceID, remoteSignalingEnvelope{Type: "tunnel_close", ConnectionID: connectionID, FromDeviceID: originDeviceID, ToDeviceID: session.fromDeviceID, Reason: reason})
	}
	if originDeviceID != session.toDeviceID {
		_ = s.sendToDevice(session.toDeviceID, remoteSignalingEnvelope{Type: "tunnel_close", ConnectionID: connectionID, FromDeviceID: originDeviceID, ToDeviceID: session.toDeviceID, Reason: reason})
	}
	remoteAppLog().Info("remote tunnel closed", zap.Uint("connectionID", connectionID), zap.Uint("originDeviceID", originDeviceID), zap.String("reason", reason))
}

func (s *remoteTunnelSession) touch(now time.Time) {
	s.lastMu.Lock()
	s.lastActivity = now
	s.lastMu.Unlock()
}

func (s *RemoteSignalingService) relay(sender *remoteSignalingConn, message remoteSignalingEnvelope) error {
	if message.ConnectionID == 0 || message.ToDeviceID == 0 || len(message.Payload) == 0 {
		return errors.New("invalid_relay_payload")
	}
	if err := validateSignalingPayload(message.Payload); err != nil {
		return err
	}
	var conn modelBiz.RemoteConnectionAttempt
	if err := global.AppDB.Where("id = ?", message.ConnectionID).First(&conn).Error; err != nil {
		return err
	}
	if conn.Status != remoteConnectionAccepted {
		return errors.New("connection_not_ready")
	}
	fromMatches := conn.FromDeviceID != nil && *conn.FromDeviceID == sender.deviceID
	toMatches := conn.ToDeviceID == sender.deviceID
	if !fromMatches && !toMatches {
		return errors.New("not_connection_party")
	}
	if message.ToDeviceID != conn.ToDeviceID && (conn.FromDeviceID == nil || message.ToDeviceID != *conn.FromDeviceID) {
		return errors.New("target_not_connection_party")
	}
	out := remoteSignalingEnvelope{Type: "relay", ConnectionID: conn.ID, FromDeviceID: sender.deviceID, ToDeviceID: message.ToDeviceID, Status: conn.Status, Payload: message.Payload}
	if !s.sendToDevice(message.ToDeviceID, out) {
		return errors.New("target_device_offline")
	}
	remoteAppLog().Info("remote signaling relay sent", zap.Uint("fromDeviceID", sender.deviceID), zap.Uint("toDeviceID", message.ToDeviceID), zap.Uint("connectionID", conn.ID), zap.String("payloadKind", signalingPayloadKindForLog(message.Payload)))
	return nil
}

func (s *RemoteSignalingService) verifyDevice(userID, deviceID uint) (modelBiz.RemoteDevice, error) {
	var device modelBiz.RemoteDevice
	if err := global.AppDB.Where("id = ? AND user_id = ?", deviceID, userID).First(&device).Error; err != nil {
		return modelBiz.RemoteDevice{}, errors.New("没有找到这台设备，请刷新后重试。")
	}
	if device.Status != remoteStatusActive || !device.RemoteEnabled {
		return modelBiz.RemoteDevice{}, errors.New("这台设备当前不可连接，请在设备上开启远程连接。")
	}
	return device, nil
}

func remoteSignalingUserMessage(err error) string {
	if err == nil {
		return "连接失败，请稍后重试。"
	}
	switch strings.TrimSpace(strings.ToLower(err.Error())) {
	case "invalid_relay_payload":
		return "连接数据不完整，请重新发起连接。"
	case "connection_not_ready":
		return "这次连接还没有准备好，请稍后重试。"
	case "not_connection_party", "target_not_connection_party":
		return "当前账号无权使用这次连接。"
	case "target_device_offline":
		return "目标设备当前离线，请打开 Mac 端 AnnaCode 后重试。"
	case "invalid_tunnel_payload", "tunnel_not_open":
		return "远程通道还没有准备好，请重新连接。"
	case "frame_too_large":
		return "单次远程数据过大，请减少内容后重试。"
	default:
		if strings.Contains(err.Error(), "_") || looksEnglishText(err.Error()) {
			return "连接失败，请稍后重试。"
		}
		return err.Error()
	}
}

func looksEnglishText(message string) bool {
	latinRun := 0
	for _, r := range message {
		switch {
		case r >= 'A' && r <= 'Z', r >= 'a' && r <= 'z':
			latinRun++
			if latinRun >= 3 {
				return true
			}
		default:
			latinRun = 0
		}
	}
	return false
}

func (s *RemoteSignalingService) sendToDevice(deviceID uint, message remoteSignalingEnvelope) bool {
	value, ok := s.connections.Load(deviceID)
	if !ok {
		return false
	}
	conn, ok := value.(*remoteSignalingConn)
	if !ok || conn.ws == nil {
		return false
	}
	return conn.send(message) == nil
}

func (c *remoteSignalingConn) send(message remoteSignalingEnvelope) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return writeRemoteSignalingJSON(c.ws, message)
}

func (c *remoteSignalingConn) writeControl(messageType int, data []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.ws == nil {
		return errors.New("websocket_closed")
	}
	return c.ws.WriteControl(messageType, data, time.Now().Add(remoteSignalingWriteWait))
}

func writeRemoteSignalingJSON(ws *gorilla.Conn, message remoteSignalingEnvelope) error {
	if ws == nil {
		return errors.New("websocket_closed")
	}
	_ = ws.SetWriteDeadline(time.Now().Add(remoteSignalingWriteWait))
	return ws.WriteJSON(message)
}

func (c *remoteSignalingConn) getLastPong() time.Time {
	c.lastPongMu.RLock()
	defer c.lastPongMu.RUnlock()
	return c.lastPong
}

func (c *remoteSignalingConn) setLastPong(value time.Time) {
	c.lastPongMu.Lock()
	defer c.lastPongMu.Unlock()
	c.lastPong = value
}

func (c *remoteSignalingConn) close() {
	c.closeOnce.Do(func() {
		close(c.closed)
		_ = c.ws.Close()
	})
}

func derefUint(value *uint) uint {
	if value == nil {
		return 0
	}
	return *value
}

func validateSignalingPayload(payload json.RawMessage) error {
	if len(payload) > maxRemoteSignalingPayloadBytes {
		return errors.New("signaling payload too large")
	}
	var body map[string]json.RawMessage
	if err := json.Unmarshal(payload, &body); err != nil {
		return errors.New("signaling payload must be json object")
	}
	if len(body) == 0 {
		return errors.New("signaling payload must not be empty")
	}
	kind, err := signalingPayloadKind(body)
	if err != nil {
		return err
	}
	switch kind {
	case "offer", "answer":
		if err := validateSignalingKeys(body, "kind", "type", "sdp"); err != nil {
			return err
		}
		return requireSignalingString(body, "sdp")
	case "candidate":
		if err := validateSignalingKeys(body, "kind", "type", "candidate", "sdpMid", "sdpMLineIndex", "usernameFragment"); err != nil {
			return err
		}
		if err := requireSignalingString(body, "candidate"); err != nil {
			return err
		}
		return validateOptionalSignalingFields(body)
	case "failed":
		if err := validateSignalingKeys(body, "kind", "type", "message"); err != nil {
			return err
		}
		return validateOptionalSignalingFields(body)
	default:
		return errors.New("unsupported signaling payload type")
	}
}

func signalingPayloadKindForLog(payload json.RawMessage) string {
	var body map[string]json.RawMessage
	if err := json.Unmarshal(payload, &body); err != nil {
		return "invalid"
	}
	kind, err := signalingPayloadKind(body)
	if err != nil {
		return "invalid"
	}
	return kind
}

func signalingPayloadKind(body map[string]json.RawMessage) (string, error) {
	kind := ""
	for _, key := range []string{"kind", "type"} {
		raw, exists := body[key]
		if !exists {
			continue
		}
		value, err := decodeSignalingString(raw)
		if err != nil {
			return "", errors.New("signaling payload type must be a string")
		}
		value = strings.TrimSpace(value)
		if value == "" {
			return "", errors.New("signaling payload type must not be empty")
		}
		if len(value) > 64 {
			return "", errors.New("signaling payload type is too long")
		}
		value = strings.ToLower(value)
		if kind != "" && kind != value {
			return "", errors.New("signaling payload type mismatch")
		}
		kind = value
	}
	if kind == "" {
		return "", errors.New("signaling payload type is required")
	}
	return kind, nil
}

func validateSignalingKeys(body map[string]json.RawMessage, allowedKeys ...string) error {
	allowed := make(map[string]struct{}, len(allowedKeys))
	for _, key := range allowedKeys {
		allowed[key] = struct{}{}
	}
	for key := range body {
		if _, ok := allowed[key]; !ok {
			return errors.New("signaling payload contains unsupported field")
		}
	}
	return nil
}

func requireSignalingString(body map[string]json.RawMessage, key string) error {
	raw, exists := body[key]
	if !exists {
		return errors.New("signaling payload missing required field")
	}
	value, err := decodeSignalingString(raw)
	if err != nil || strings.TrimSpace(value) == "" {
		return errors.New("signaling payload field must be a non-empty string")
	}
	return nil
}

func validateOptionalSignalingFields(body map[string]json.RawMessage) error {
	for key, raw := range body {
		switch key {
		case "kind", "type", "candidate", "message", "sdpMid", "usernameFragment":
			if isJSONNull(raw) {
				continue
			}
			if _, err := decodeSignalingString(raw); err != nil {
				return errors.New("signaling payload field must be a string")
			}
		case "sdpMLineIndex":
			if isJSONNull(raw) {
				continue
			}
			var value float64
			if err := json.Unmarshal(raw, &value); err != nil || value < 0 || value != float64(int(value)) {
				return errors.New("signaling payload line index must be a non-negative integer")
			}
		}
	}
	return nil
}

func decodeSignalingString(raw json.RawMessage) (string, error) {
	var value string
	if err := json.Unmarshal(raw, &value); err != nil {
		return "", err
	}
	return value, nil
}

func isJSONNull(raw json.RawMessage) bool {
	return strings.EqualFold(strings.TrimSpace(string(raw)), "null")
}
