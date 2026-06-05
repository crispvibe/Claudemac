package response

type DashboardMetric struct {
	Key        string  `json:"key"`
	Title      string  `json:"title"`
	Value      int64   `json:"value"`
	ChangeRate float64 `json:"changeRate"`
	ChangeText string  `json:"changeText"`
	Trend      []int64 `json:"trend"`
}

type DashboardHealth struct {
	Title       string `json:"title"`
	Value       string `json:"value"`
	Description string `json:"description"`
	Status      string `json:"status"`
}

type DashboardTrend struct {
	Title      string   `json:"title"`
	SeriesName string   `json:"seriesName"`
	Labels     []string `json:"labels"`
	Values     []int64  `json:"values"`
}

type DashboardNotice struct {
	Level      string `json:"level"`
	LevelTitle string `json:"levelTitle"`
	Title      string `json:"title"`
	Time       string `json:"time"`
}

type DashboardShortcut struct {
	Title     string `json:"title"`
	RouteName string `json:"routeName"`
}

type RemoteSLIPoint struct {
	Label string  `json:"label"`
	Value float64 `json:"value"`
}

type RemoteSLIReason struct {
	Reason string `json:"reason"`
	Total  int64  `json:"total"`
}

type RemoteSLIDashboard struct {
	Labels                   []string          `json:"labels"`
	ConnectionSuccessRate    []*float64        `json:"connectionSuccessRate"`
	P2PRatio                 []*float64        `json:"p2pRatio"`
	FirstPacketLatencyMS     []*float64        `json:"firstPacketLatencyMs"`
	DeviceOnlineCount        int64             `json:"deviceOnlineCount"`
	DeviceCodeResolveSuccess int64             `json:"deviceCodeResolveSuccess"`
	DeviceCodeResolveFailed  int64             `json:"deviceCodeResolveFailed"`
	RejectionReasons         []RemoteSLIReason `json:"rejectionReasons"`
	HasTransportSamples      bool              `json:"hasTransportSamples"`
}

type DashboardPanel struct {
	Metrics   []DashboardMetric   `json:"metrics"`
	Health    DashboardHealth     `json:"health"`
	Trend     DashboardTrend      `json:"trend"`
	Notices   []DashboardNotice   `json:"notices"`
	Shortcuts []DashboardShortcut `json:"shortcuts"`
	RemoteSLI RemoteSLIDashboard  `json:"remoteSli"`
}
