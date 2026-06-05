package biz

import (
	"fmt"
	"sort"
	"time"

	"heyu/server/global"
	"heyu/server/model/admin"
	modelBiz "heyu/server/model/biz"
	bizRes "heyu/server/model/biz/response"
)

type DashboardService struct{}

type dailyCount struct {
	Day   string `gorm:"column:day"`
	Total int64  `gorm:"column:total"`
}

func (s *DashboardService) GetPanel(roleID uint) (bizRes.DashboardPanel, error) {
	now := time.Now()
	loginTrend, err := s.getDailyCounts(&admin.LoginLog{}, 8, "status = ?", true)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	accountTrend, err := s.getDailyCounts(&admin.Account{}, 8)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	operationTrend, err := s.getDailyCounts(&admin.OperationRecord{}, 8)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	activityTrend, err := s.getDailyCounts(&admin.LoginLog{}, 30, "status = ?", true)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}

	registeredAPI, err := s.countModel(&admin.APICatalogEntry{})
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	fileCount, err := s.countModel(&admin.FileUploadAndDownload{})
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	categoryCount, err := s.countModel(&admin.AttachmentCategory{})
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	failedLoginToday, err := s.countToday(&admin.LoginLog{}, "status = ?", false)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}

	routeCount := int64(len(global.AppRouters))
	coverage := 100.0
	if routeCount > 0 {
		coverage = float64(registeredAPI) * 100 / float64(routeCount)
		if coverage > 100 {
			coverage = 100
		}
	}

	panel := bizRes.DashboardPanel{
		Metrics: []bizRes.DashboardMetric{
			buildMetric("loginToday", "今日成功登录", loginTrend),
			buildMetric("accountToday", "今日新增账号", accountTrend),
			buildMetric("operationToday", "今日操作记录", operationTrend),
		},
		Health: bizRes.DashboardHealth{
			Title:       "系统纳管覆盖率",
			Value:       fmt.Sprintf("%.1f%%", coverage),
			Description: fmt.Sprintf("已登记 %d/%d 条接口，严格权限%s", registeredAPI, routeCount, boolLabel(global.AppConfig.System.UseStrictAuth, "已开启", "未开启")),
			Status:      healthStatus(coverage, global.AppConfig.System.UseStrictAuth),
		},
		Trend: bizRes.DashboardTrend{
			Title:      "近30天系统活跃趋势",
			SeriesName: "登录次数",
			Labels:     activityTrend.labels,
			Values:     activityTrend.values,
		},
		Notices:   s.buildNotices(now, routeCount, registeredAPI, failedLoginToday, fileCount, categoryCount),
		Shortcuts: s.buildShortcuts(roleID),
	}
	remoteSLI, err := s.getRemoteSLIDashboard(8)
	if err != nil {
		return bizRes.DashboardPanel{}, err
	}
	panel.RemoteSLI = remoteSLI
	return panel, nil
}

type remoteSLIRow struct {
	Day          string  `gorm:"column:day"`
	Decided      int64   `gorm:"column:decided"`
	Accepted     int64   `gorm:"column:accepted"`
	P2P          int64   `gorm:"column:p2p"`
	Transported  int64   `gorm:"column:transported"`
	AvgFirstMS   float64 `gorm:"column:avg_first_ms"`
	FirstSamples int64   `gorm:"column:first_samples"`
}

type trendData struct {
	labels []string
	values []int64
}

func (s *DashboardService) getRemoteSLIDashboard(days int) (bizRes.RemoteSLIDashboard, error) {
	if days <= 0 {
		return bizRes.RemoteSLIDashboard{}, nil
	}
	start := dayStart(time.Now().AddDate(0, 0, -(days - 1)))
	var rows []remoteSLIRow
	err := global.AppDB.Model(&modelBiz.RemoteConnectionAttempt{}).
		Select("DATE(created_at) as day, SUM(CASE WHEN status IN ('accepted','rejected') THEN 1 ELSE 0 END) as decided, SUM(CASE WHEN status = 'accepted' THEN 1 ELSE 0 END) as accepted, SUM(CASE WHEN transport = 'p2p' THEN 1 ELSE 0 END) as p2p, SUM(CASE WHEN transport = 'p2p' THEN 1 ELSE 0 END) as transported, AVG(first_packet_latency_ms) as avg_first_ms, SUM(CASE WHEN first_packet_latency_ms IS NOT NULL THEN 1 ELSE 0 END) as first_samples").
		Where("created_at >= ?", start).
		Group("DATE(created_at)").Order("day asc").Scan(&rows).Error
	if err != nil {
		return bizRes.RemoteSLIDashboard{}, err
	}
	rowMap := make(map[string]remoteSLIRow, len(rows))
	for _, row := range rows {
		rowMap[row.Day] = row
	}
	result := bizRes.RemoteSLIDashboard{
		Labels:                make([]string, 0, days),
		ConnectionSuccessRate: make([]*float64, 0, days),
		P2PRatio:              make([]*float64, 0, days),
		FirstPacketLatencyMS:  make([]*float64, 0, days),
	}
	for i := 0; i < days; i++ {
		day := start.AddDate(0, 0, i)
		key := day.Format("2006-01-02")
		row := rowMap[key]
		result.Labels = append(result.Labels, day.Format("01-02"))
		result.ConnectionSuccessRate = append(result.ConnectionSuccessRate, percentPtr(row.Accepted, row.Decided))
		result.P2PRatio = append(result.P2PRatio, percentPtr(row.P2P, row.Transported))
		if row.FirstSamples > 0 {
			avg := row.AvgFirstMS
			result.FirstPacketLatencyMS = append(result.FirstPacketLatencyMS, &avg)
		} else {
			result.FirstPacketLatencyMS = append(result.FirstPacketLatencyMS, nil)
		}
		if row.Transported > 0 {
			result.HasTransportSamples = true
		}
	}
	if err := global.AppDB.Model(&modelBiz.RemoteDevice{}).Where("status = ? AND last_seen_at >= ?", remoteStatusActive, time.Now().Add(-2*time.Minute)).Count(&result.DeviceOnlineCount).Error; err != nil {
		return bizRes.RemoteSLIDashboard{}, err
	}
	if err := global.AppDB.Model(&modelBiz.RemoteDeviceCodeAttempt{}).Where("created_at >= ? AND status = ?", start, "success").Count(&result.DeviceCodeResolveSuccess).Error; err != nil {
		return bizRes.RemoteSLIDashboard{}, err
	}
	if err := global.AppDB.Model(&modelBiz.RemoteDeviceCodeAttempt{}).Where("created_at >= ? AND status <> ?", start, "success").Count(&result.DeviceCodeResolveFailed).Error; err != nil {
		return bizRes.RemoteSLIDashboard{}, err
	}
	if err := global.AppDB.Model(&modelBiz.RemoteConnectionAttempt{}).
		Select("COALESCE(NULLIF(reason, ''), 'unknown') as reason, COUNT(*) as total").
		Where("created_at >= ? AND status = ?", start, remoteConnectionRejected).
		Group("COALESCE(NULLIF(reason, ''), 'unknown')").Order("total desc").Limit(8).
		Scan(&result.RejectionReasons).Error; err != nil {
		return bizRes.RemoteSLIDashboard{}, err
	}
	return result, nil
}

func percent(part, total int64) float64 {
	if total <= 0 {
		return 0
	}
	return float64(part) * 100 / float64(total)
}

func percentPtr(part, total int64) *float64 {
	if total <= 0 {
		return nil
	}
	value := percent(part, total)
	return &value
}

func (s *DashboardService) getDailyCounts(model any, days int, conditions ...any) (trendData, error) {
	if days <= 0 {
		return trendData{}, nil
	}
	start := time.Now().AddDate(0, 0, -(days - 1))
	db := global.AppDB.Model(model).Where("created_at >= ?", dayStart(start))
	if len(conditions) > 0 {
		query, _ := conditions[0].(string)
		args := []any{}
		if len(conditions) > 1 {
			args = conditions[1:]
		}
		db = db.Where(query, args...)
	}
	var rows []dailyCount
	if err := db.Select("DATE(created_at) as day, COUNT(*) as total").Group("DATE(created_at)").Order("day asc").Scan(&rows).Error; err != nil {
		return trendData{}, err
	}
	rowMap := make(map[string]int64, len(rows))
	for _, row := range rows {
		rowMap[row.Day] = row.Total
	}
	labels := make([]string, 0, days)
	values := make([]int64, 0, days)
	for i := 0; i < days; i++ {
		day := start.AddDate(0, 0, i)
		key := day.Format("2006-01-02")
		labels = append(labels, day.Format("01-02"))
		values = append(values, rowMap[key])
	}
	return trendData{labels: labels, values: values}, nil
}

func (s *DashboardService) countToday(model any, conditions ...any) (int64, error) {
	var total int64
	db := global.AppDB.Model(model).Where("created_at >= ?", dayStart(time.Now()))
	if len(conditions) > 0 {
		query, _ := conditions[0].(string)
		args := []any{}
		if len(conditions) > 1 {
			args = conditions[1:]
		}
		db = db.Where(query, args...)
	}
	if err := db.Count(&total).Error; err != nil {
		return 0, err
	}
	return total, nil
}

func (s *DashboardService) countModel(model any) (int64, error) {
	var total int64
	if err := global.AppDB.Model(model).Count(&total).Error; err != nil {
		return 0, err
	}
	return total, nil
}

// buildNotices 聚合多维度运行态提醒：架构 / 安全 / 登录 / 性能 / 账号 / 存储。
// 每条通知使用事件真实时间，并按严重级别排序（风险 → 警告 → 公告 → 信息 → 通知）。
func (s *DashboardService) buildNotices(now time.Time, routeCount, registeredAPI, failedLoginToday, fileCount, categoryCount int64) []bizRes.DashboardNotice {
	notices := make([]bizRes.DashboardNotice, 0, 10)
	nowStamp := now.Format("01-02 15:04")

	// ── 架构：路由与接口名录一致性 ────────────────────────────────
	if routeCount > 0 && registeredAPI > 0 {
		diff := routeCount - registeredAPI
		switch {
		case diff > 0:
			notices = append(notices, bizRes.DashboardNotice{Level: "warning", LevelTitle: "架构", Title: fmt.Sprintf("运行中路由 %d 条多于已登记接口 %d 条，建议在接口配置中补录缺失的 %d 条。", routeCount, registeredAPI, diff), Time: nowStamp})
		case diff < 0:
			notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "架构", Title: fmt.Sprintf("接口名录 %d 条含 %d 条冗余记录，运行路由仅 %d 条，建议清理历史接口。", registeredAPI, -diff, routeCount), Time: nowStamp})
		default:
			notices = append(notices, bizRes.DashboardNotice{Level: "success", LevelTitle: "架构", Title: fmt.Sprintf("接口名录已与运行路由对齐，共 %d 条。", routeCount), Time: nowStamp})
		}
	}

	// ── 安全：严格权限模式 ──────────────────────────────────────
	if global.AppConfig.System.UseStrictAuth {
		notices = append(notices, bizRes.DashboardNotice{Level: "success", LevelTitle: "安全", Title: "严格权限模式已开启，角色仅能访问授权范围内的菜单与接口。", Time: nowStamp})
	} else {
		notices = append(notices, bizRes.DashboardNotice{Level: "warning", LevelTitle: "安全", Title: "严格权限模式当前未开启，建议在系统配置中开启以强化角色隔离。", Time: nowStamp})
	}

	// ── 安全：登录验证码策略（-1 禁用 / 0 每次 / >0 阈值） ─────────
	switch openCaptcha := global.AppConfig.Captcha.OpenCaptcha; {
	case openCaptcha < 0:
		notices = append(notices, bizRes.DashboardNotice{Level: "danger", LevelTitle: "安全", Title: "登录验证码已被禁用，请在安全设置中重新开启以防暴力破解。", Time: nowStamp})
	case openCaptcha == 0:
		notices = append(notices, bizRes.DashboardNotice{Level: "success", LevelTitle: "安全", Title: "登录验证码为每次登录强制启用，防护等级：高。", Time: nowStamp})
	default:
		notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "安全", Title: fmt.Sprintf("登录验证码将在累计失败 %d 次后触发，统计窗口 %ds。", openCaptcha, global.AppConfig.Captcha.OpenCaptchaTimeOut), Time: nowStamp})
	}

	// ── 登录：近 24h 失败统计 + 唯一 IP ────────────────────────
	if failedLoginToday > 0 {
		uniqueIPs, _ := s.countDistinctLoginIPs(false, dayStart(now))
		lastFailedTime := s.lastLoginTime(false)
		level := "warning"
		levelLabel := "风险"
		if failedLoginToday >= 10 || uniqueIPs >= 5 {
			level = "danger"
			levelLabel = "高危"
		}
		notices = append(notices, bizRes.DashboardNotice{Level: level, LevelTitle: levelLabel, Title: fmt.Sprintf("今日累计 %d 次登录失败，涉及 %d 个 IP，请核查是否存在暴力破解或凭据泄漏。", failedLoginToday, uniqueIPs), Time: stampOrFallback(lastFailedTime, nowStamp)})
	}

	// ── 登录：近期成功登录时间 ─────────────────────────────────
	if lastLogin := s.lastLoginTime(true); !lastLogin.IsZero() {
		notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "登录", Title: fmt.Sprintf("最近一次成功登录：%s。", lastLogin.Format("2006-01-02 15:04")), Time: lastLogin.Format("01-02 15:04")})
	}

	// ── 性能：近 7 日接口平均延迟（来自 operation_logs） ─────────
	if avgLatency, sampleCount, err := s.recentAverageLatency(7); err == nil && sampleCount > 0 {
		switch {
		case avgLatency >= 500:
			notices = append(notices, bizRes.DashboardNotice{Level: "warning", LevelTitle: "性能", Title: fmt.Sprintf("近 7 日接口平均延迟 %dms（样本 %d 条），建议排查慢查询或外部依赖。", avgLatency, sampleCount), Time: nowStamp})
		case avgLatency >= 200:
			notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "性能", Title: fmt.Sprintf("近 7 日接口平均延迟 %dms，总体处于正常区间。", avgLatency), Time: nowStamp})
		default:
			notices = append(notices, bizRes.DashboardNotice{Level: "success", LevelTitle: "性能", Title: fmt.Sprintf("近 7 日接口平均延迟仅 %dms，响应表现良好。", avgLatency), Time: nowStamp})
		}
	}

	// ── 账号：冻结与总数 ──────────────────────────────────────
	if totalAccounts, disabledAccounts, err := s.accountSummary(); err == nil && totalAccounts > 0 {
		if disabledAccounts > 0 {
			notices = append(notices, bizRes.DashboardNotice{Level: "warning", LevelTitle: "账号", Title: fmt.Sprintf("当前 %d 个账号中有 %d 个处于冻结状态，注意及时清理过期成员。", totalAccounts, disabledAccounts), Time: nowStamp})
		} else if totalAccounts <= 1 {
			notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "账号", Title: "仅存在一个管理员账号，建议补充至少一个应急管理员以防锁定。", Time: nowStamp})
		}
	}

	// ── 安全：JWT 黑名单体量 ──────────────────────────────────
	if blacklisted, _ := s.countModel(&admin.JwtBlacklist{}); blacklisted >= 1000 {
		notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "安全", Title: fmt.Sprintf("JWT 黑名单已累计 %d 条，可通过定时任务清理过期记录。", blacklisted), Time: nowStamp})
	}

	// ── 存储：媒体库现状 ──────────────────────────────────────
	if categoryCount == 0 && fileCount == 0 {
		notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "存储", Title: "媒体库尚未录入分类与文件，附件选择链路暂不可用。", Time: nowStamp})
	} else {
		notices = append(notices, bizRes.DashboardNotice{Level: "info", LevelTitle: "存储", Title: fmt.Sprintf("媒体库已收录 %d 个分类、%d 个文件，可直接在业务中引用。", categoryCount, fileCount), Time: nowStamp})
	}

	sort.SliceStable(notices, func(i, j int) bool {
		return noticePriority(notices[i].Level) > noticePriority(notices[j].Level)
	})
	return notices
}

// recentAverageLatency 基于 operation_logs 计算近 N 天的平均响应延迟（毫秒）。
func (s *DashboardService) recentAverageLatency(days int) (int64, int64, error) {
	if days <= 0 {
		return 0, 0, nil
	}
	var result struct {
		Avg   float64 `gorm:"column:avg_latency"`
		Total int64   `gorm:"column:total"`
	}
	start := dayStart(time.Now().AddDate(0, 0, -(days - 1)))
	err := global.AppDB.Model(&admin.OperationRecord{}).
		Select("AVG(latency) as avg_latency, COUNT(*) as total").
		Where("created_at >= ? AND latency > 0", start).
		Scan(&result).Error
	if err != nil {
		return 0, 0, err
	}
	// latency 存储为纳秒，转换为毫秒。
	avgMs := int64(result.Avg / 1e6)
	return avgMs, result.Total, nil
}

// accountSummary 返回启用账号总数与冻结账号数。
func (s *DashboardService) accountSummary() (int64, int64, error) {
	var total, disabled int64
	if err := global.AppDB.Model(&admin.Account{}).Count(&total).Error; err != nil {
		return 0, 0, err
	}
	if err := global.AppDB.Model(&admin.Account{}).Where("enable = ?", 2).Count(&disabled).Error; err != nil {
		return 0, 0, err
	}
	return total, disabled, nil
}

// countDistinctLoginIPs 返回一段时间内登录成功或失败的唯一 IP 数。
func (s *DashboardService) countDistinctLoginIPs(success bool, since time.Time) (int64, error) {
	var total int64
	err := global.AppDB.Model(&admin.LoginLog{}).
		Where("created_at >= ? AND status = ?", since, success).
		Distinct("ip").
		Count(&total).Error
	return total, err
}

// lastLoginTime 返回最近一条成功/失败登录日志的时间，若无记录返回零值。
func (s *DashboardService) lastLoginTime(success bool) time.Time {
	var record admin.LoginLog
	if err := global.AppDB.Model(&admin.LoginLog{}).
		Where("status = ?", success).
		Order("created_at desc").
		Limit(1).
		First(&record).Error; err != nil {
		return time.Time{}
	}
	if record.CreatedAt.IsZero() {
		return time.Time{}
	}
	return record.CreatedAt
}

// stampOrFallback 返回事件时间文案，若为零值则回退到 fallback。
func stampOrFallback(t time.Time, fallback string) string {
	if t.IsZero() {
		return fallback
	}
	return t.Format("01-02 15:04")
}

// noticePriority 定义通知展示权重：数字越大越优先展示。
func noticePriority(level string) int {
	switch level {
	case "danger":
		return 5
	case "warning":
		return 4
	case "info":
		return 2
	case "success":
		return 1
	default:
		return 0
	}
}

func (s *DashboardService) buildShortcuts(roleID uint) []bizRes.DashboardShortcut {
	var menuIDs []uint
	if err := global.AppDB.Model(&admin.RoleNavigationBinding{}).Where("role_id = ?", roleID).Pluck("navigation_entry_id", &menuIDs).Error; err != nil || len(menuIDs) == 0 {
		return defaultShortcuts()
	}
	var menus []admin.NavigationEntry
	if err := global.AppDB.Where("id IN ?", menuIDs).
		Where("name NOT IN ?", []string{"dashboard", "home", "systemSettings"}).
		Order("sort asc, id asc").
		Find(&menus).Error; err != nil {
		return defaultShortcuts()
	}
	shortcuts := make([]bizRes.DashboardShortcut, 0, 4)
	for _, menu := range menus {
		if menu.Name == "" || menu.Meta.Title == "" {
			continue
		}
		shortcuts = append(shortcuts, bizRes.DashboardShortcut{Title: menu.Meta.Title, RouteName: menu.Name})
		if len(shortcuts) == 4 {
			break
		}
	}
	if len(shortcuts) == 0 {
		return defaultShortcuts()
	}
	sort.SliceStable(shortcuts, func(i, j int) bool {
		return shortcuts[i].Title < shortcuts[j].Title
	})
	return shortcuts
}

func buildMetric(key, title string, trend trendData) bizRes.DashboardMetric {
	current := lastValue(trend.values)
	previous := int64(0)
	if len(trend.values) > 1 {
		previous = trend.values[len(trend.values)-2]
	}
	changeText, changeRate := buildChange(current, previous)
	return bizRes.DashboardMetric{
		Key:        key,
		Title:      title,
		Value:      current,
		ChangeRate: changeRate,
		ChangeText: changeText,
		Trend:      trend.values,
	}
}

func buildChange(current, previous int64) (string, float64) {
	if previous == 0 {
		if current == 0 {
			return "较昨日持平", 0
		}
		return "较昨日新增", 100
	}
	rate := float64(current-previous) * 100 / float64(previous)
	if rate == 0 {
		return "较昨日持平", 0
	}
	if rate > 0 {
		return fmt.Sprintf("较昨日 +%.1f%%", rate), rate
	}
	return fmt.Sprintf("较昨日 %.1f%%", rate), rate
}

func lastValue(values []int64) int64 {
	if len(values) == 0 {
		return 0
	}
	return values[len(values)-1]
}

func defaultShortcuts() []bizRes.DashboardShortcut {
	return []bizRes.DashboardShortcut{
		{Title: "导航配置", RouteName: "navigation"},
		{Title: "接口配置", RouteName: "apiCatalog"},
		{Title: "权限分组", RouteName: "roles"},
		{Title: "账号管理", RouteName: "accounts"},
	}
}

func boolLabel(value bool, yes, no string) string {
	if value {
		return yes
	}
	return no
}

func healthStatus(coverage float64, strictAuth bool) string {
	if coverage >= 95 && strictAuth {
		return "success"
	}
	if coverage >= 80 {
		return "warning"
	}
	return "danger"
}

func dayStart(t time.Time) time.Time {
	year, month, day := t.Date()
	return time.Date(year, month, day, 0, 0, 0, 0, t.Location())
}
