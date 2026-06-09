package biz

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/require"
	"heyu/server/global"
	modelBiz "heyu/server/model/biz"
)

func TestValidateSignalingPayloadAllowsWebRTCMetadata(t *testing.T) {
	cases := []string{
		`{"kind":"offer","sdp":"v=0"}`,
		`{"type":"answer","sdp":"v=0"}`,
		`{"kind":"candidate","candidate":"candidate:1 1 udp 2122260223 192.0.2.1 54400 typ host","sdpMid":"0","sdpMLineIndex":0}`,
		`{"kind":"failed","message":"ice failed"}`,
	}
	for _, tc := range cases {
		require.NoError(t, validateSignalingPayload(json.RawMessage(tc)), tc)
	}
}

func TestValidateSignalingPayloadRejectsBusinessFrames(t *testing.T) {
	cases := []string{
		`{"kind":"command","command":{"op":"stop"}}`,
		`{"kind":"panel_state","snapshot":{}}`,
		`{"kind":"offer","sdp":"v=0","data":"business"}`,
		`{"kind":"candidate","candidate":"candidate:1","frame":"{}"}`,
		`{"kind":"offer","sdp":"v=0","messageBody":"hello"}`,
		`{"kind":"offer","sdp":"v=0","payload":{"command":"stop"}}`,
	}
	for _, tc := range cases {
		require.Error(t, validateSignalingPayload(json.RawMessage(tc)), tc)
	}
}

func TestRelayRejectsPendingConnection(t *testing.T) {
	setupRemoteServiceTest(t)
	fromDevice := modelBiz.RemoteDevice{UserID: 1, DeviceUID: "ios-1", DeviceType: "ios", Platform: "ios", DeviceName: "iPhone", DevicePublicKey: "pk", RemoteEnabled: true, Status: remoteStatusActive}
	target := modelBiz.RemoteDevice{UserID: 2, DeviceUID: "mac-1", DeviceType: remoteDeviceTypeDesktop, Platform: "macos", DeviceName: "Mac", DevicePublicKey: "pk", ApprovalPolicy: remoteApprovalAlwaysAsk, RemoteEnabled: true, Status: remoteStatusActive}
	require.NoError(t, global.AppDB.Create(&fromDevice).Error)
	require.NoError(t, global.AppDB.Create(&target).Error)
	conn := modelBiz.RemoteConnectionAttempt{FromUserID: 1, FromDeviceID: &fromDevice.ID, ToUserID: 2, ToDeviceID: target.ID, Status: remoteConnectionPending, Reason: "waiting_for_approval"}
	require.NoError(t, global.AppDB.Create(&conn).Error)

	err := (&RemoteSignalingService{}).relay(
		&remoteSignalingConn{userID: fromDevice.UserID, deviceID: fromDevice.ID},
		remoteSignalingEnvelope{ConnectionID: conn.ID, ToDeviceID: target.ID, Payload: json.RawMessage(`{"kind":"offer","sdp":"v=0"}`)},
	)
	require.Error(t, err)
	require.Equal(t, "connection_not_ready", err.Error())
}
