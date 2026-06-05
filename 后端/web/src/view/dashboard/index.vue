 <template>
   <div class="h-full w-full overflow-y-auto bg-transparent text-[#1d1d1f] transition-colors duration-300 p-2 lg:p-4 box-border">
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 xl:gap-6 mb-6">
      <app-card custom-class="hover:-translate-y-1 transition-transform">
        <app-chart :type="1" :title="metricAt(0).title" :metric="metricAt(0)" />
      </app-card>
      <app-card custom-class="hover:-translate-y-1 transition-transform">
        <app-chart :type="2" :title="metricAt(1).title" :metric="metricAt(1)" />
      </app-card>
      <app-card custom-class="hover:-translate-y-1 transition-transform">
        <app-chart :type="3" :title="metricAt(2).title" :metric="metricAt(2)" />
      </app-card>
      <app-card custom-class="hover:-translate-y-1 transition-transform bg-gradient-to-br from-[#1f83ff] to-[#0ea5e9] text-white !border-none !shadow-[0_12px_32px_rgba(31,131,255,0.3)] block">
        <template #default>
          <div class="flex justify-between items-center mb-1">
             <div class="text-[16px] font-semibold tracking-tight text-white/90">{{ panel.health.title }}</div>
          </div>
          <div class="flex flex-col h-full justify-center mt-6">
             <div class="text-[40px] leading-tight font-black mb-2 text-white">{{ panel.health.value }}</div>
             <div class="text-sm text-white/80 flex items-center gap-2">
                <span class="w-2 h-2 rounded-full bg-green-300 animate-pulse"></span>
                {{ panel.health.description }}
             </div>
          </div>
        </template>
      </app-card>
    </div>

    <app-card title="远程连接 SLI" custom-class="mb-6">
      <div class="remote-sli-grid">
        <div class="remote-sli-card">
          <div class="remote-sli-title">连接成功率</div>
          <div v-if="hasLatestRemoteValue('connectionSuccessRate')" class="remote-sli-value">{{ latestRemoteValue('connectionSuccessRate') }}%</div>
          <div v-else class="remote-sli-empty">暂无样本</div>
          <div class="remote-sli-bars"><span v-for="(value, index) in panel.remoteSli.connectionSuccessRate" :key="`success-${index}`" :style="barStyle(value)" /></div>
        </div>
        <div class="remote-sli-card">
          <div class="remote-sli-title">P2P 比例</div>
          <div v-if="panel.remoteSli.hasTransportSamples && hasLatestRemoteValue('p2pRatio')" class="remote-sli-value">{{ latestRemoteValue('p2pRatio') }}%</div>
          <div v-else class="remote-sli-empty">暂无 P2P/TURN 样本</div>
          <div class="remote-sli-bars"><span v-for="(value, index) in panel.remoteSli.p2pRatio" :key="`p2p-${index}`" :style="barStyle(value)" /></div>
        </div>
        <div class="remote-sli-card">
          <div class="remote-sli-title">首包延迟</div>
          <div v-if="hasLatestRemoteValue('firstPacketLatencyMs')" class="remote-sli-value">{{ latestRemoteValue('firstPacketLatencyMs') }}ms</div>
          <div v-else class="remote-sli-empty">暂无样本</div>
          <div class="remote-sli-bars"><span v-for="(value, index) in panel.remoteSli.firstPacketLatencyMs" :key="`first-${index}`" :style="barStyle(latencyToPercent(value))" /></div>
        </div>
        <div class="remote-sli-card">
          <div class="remote-sli-title">设备/设备码</div>
          <div class="remote-sli-meta">在线设备 {{ panel.remoteSli.deviceOnlineCount }}</div>
          <div class="remote-sli-meta">设备码解析 成功 {{ panel.remoteSli.deviceCodeResolveSuccess }} / 失败 {{ panel.remoteSli.deviceCodeResolveFailed }}</div>
          <div class="remote-sli-reasons">拒绝原因：{{ rejectionReasonsText }}</div>
        </div>
      </div>
    </app-card>

    <div class="grid grid-cols-1 xl:grid-cols-3 gap-4 xl:gap-6">
      <div class="xl:col-span-2">
        <app-card :title="panel.trend.title">
          <app-chart :type="4" :trend="panel.trend" />
        </app-card>
      </div>

      <div class="xl:col-span-1 flex flex-col gap-4 xl:gap-6">
        <app-card title="快捷运营通道">
          <app-quick-link :shortcuts="panel.shortcuts" />
        </app-card>
        <app-card title="系统核心公告" show-action>
          <app-notice :notices="panel.notices" />
        </app-card>
      </div>
    </div>
  </div>
</template>

<script setup>
  import { computed, onMounted, reactive } from 'vue'
  import { getDashboardPanel } from '@/api/dashboard'
  import {
    AppChart,
    AppNotice,
    AppQuickLink,
    AppCard
  } from './components'

  defineOptions({
    name: 'OverviewScenePage'
  })

  const createMetric = () => ({
    title: '加载中',
    value: 0,
    changeText: '较昨日持平',
    trend: []
  })

  const panel = reactive({
    metrics: [createMetric(), createMetric(), createMetric()],
    health: {
      title: '系统纳管覆盖率',
      value: '--',
      description: '',
      status: 'warning'
    },
    trend: {
      title: '近30天系统活跃趋势',
      seriesName: '登录次数',
      labels: [],
      values: []
    },
    notices: [],
    shortcuts: [],
    remoteSli: {
      labels: [],
      connectionSuccessRate: [],
      p2pRatio: [],
      firstPacketLatencyMs: [],
      deviceOnlineCount: 0,
      deviceCodeResolveSuccess: 0,
      deviceCodeResolveFailed: 0,
      rejectionReasons: [],
      hasTransportSamples: false
    }
  })

  const metricAt = (index) => {
    return panel.metrics[index] || createMetric()
  }

  const latestRemoteValue = (key) => {
    const values = panel.remoteSli[key]
    if (!Array.isArray(values) || values.length === 0) return null
    const latest = [...values].reverse().find(value => value !== null && value !== undefined && value !== '')
    if (latest === undefined) return null
    return Number(latest).toFixed(1)
  }

  const hasLatestRemoteValue = (key) => latestRemoteValue(key) !== null

  const latencyToPercent = (value) => Math.max(0, Math.min(100, 100 - Number(value || 0) / 10))
  const barStyle = (value) => ({ height: `${Math.max(4, Math.min(100, Number(value || 0)))}%` })
  const rejectionReasonsText = computed(() => {
    const reasons = panel.remoteSli.rejectionReasons || []
    if (!reasons.length) return '暂无'
    return reasons.map(item => `${item.reason || 'unknown'} ${item.total}`).join(' / ')
  })

  const loadPanel = async () => {
    const res = await getDashboardPanel()
    if (res.code !== 0) {
      return
    }
    panel.metrics = Array.isArray(res.data.metrics) && res.data.metrics.length ? res.data.metrics : panel.metrics
    panel.health = res.data.health || panel.health
    panel.trend = res.data.trend || panel.trend
    panel.notices = Array.isArray(res.data.notices) ? res.data.notices : []
    panel.shortcuts = Array.isArray(res.data.shortcuts) ? res.data.shortcuts : []
    panel.remoteSli = res.data.remoteSli || panel.remoteSli
  }

  onMounted(() => {
    loadPanel()
  })
</script>

<style lang="scss" scoped>
.remote-sli-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 14px;
}
.remote-sli-card {
  border: 1px solid rgba(15, 23, 42, 0.08);
  border-radius: 16px;
  padding: 14px;
  background: rgba(255, 255, 255, 0.72);
}
.remote-sli-title { font-size: 13px; color: #64748b; margin-bottom: 8px; }
.remote-sli-value { font-size: 26px; font-weight: 800; color: #0f172a; }
.remote-sli-empty { font-size: 13px; color: #94a3b8; min-height: 32px; display: flex; align-items: center; }
.remote-sli-meta, .remote-sli-reasons { font-size: 13px; color: #475569; line-height: 1.8; }
.remote-sli-bars { height: 48px; display: flex; align-items: flex-end; gap: 4px; margin-top: 12px; }
.remote-sli-bars span { flex: 1; min-width: 8px; border-radius: 999px 999px 0 0; background: linear-gradient(180deg, #38bdf8, #2563eb); }

/* 收敛大盘独立组件滚动条，不喧宾夺主 */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-thumb {
  background: rgba(0,0,0,0.1);
  border-radius: 10px;
}
</style>
