<template>
  <Chart :height="height" :option="chartOption" />
</template>

<script setup>
  import Chart from '@/components/charts/index.vue'
  import useChartOption from '@/hooks/charts'
  import { graphic } from '@/components/charts/runtime'
  import { computed, ref } from 'vue'
  import { useAppStore } from '@/pinia'
  import { storeToRefs } from 'pinia'
  const appStore = useAppStore()
  const { config } = storeToRefs(appStore)
  const prop = defineProps({
    height: {
      type: String,
      default: '128px'
    },
    labels: {
      type: Array,
      default: () => []
    },
    data: {
      type: Array,
      default: () => []
    },
    seriesName: {
      type: String,
      default: '趋势值'
    }
  })
  const axisTextColor = computed(() => {
    return appStore.isDark ? 'rgba(255,255,255,0.70)' : 'rgba(0,0,0,0.70)'
  })
  const dotColor = computed(() => {
    return appStore.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)'
  })
  const graphicFactory = (side) => {
    return {
      type: 'text',
      bottom: '8',
      ...side,
      style: {
        text: '',
        textAlign: 'center',
        fill: axisTextColor.value,
        fontSize: 12
      }
    }
  }
  const xAxis = computed(() => prop.labels)
  const chartsData = computed(() => prop.data)
  const graphicElements = ref([
    graphicFactory({ left: '5%' }),
    graphicFactory({ right: 0 })
  ])
  const { chartOption } = useChartOption(() => {
    return {
      grid: {
        left: '40',
        right: '0',
        top: '10',
        bottom: '30'
      },
      xAxis: {
        type: 'category',
        offset: 2,
        data: xAxis.value,
        boundaryGap: false,
        axisLabel: {
          color: axisTextColor.value,
          formatter(value, idx) {
            if (idx === 0) return ''
            if (idx === xAxis.value.length - 1) return ''
            return `${value}`
          }
        },
        axisLine: {
          show: false
        },
        axisTick: {
          show: false
        },
        splitLine: {
          show: true,
          interval: (idx) => {
            if (idx === 0) return false
            if (idx === xAxis.value.length - 1) return false
            return true
          },
          lineStyle: {
            color: dotColor.value
          }
        },
        axisPointer: {
          show: true,
          lineStyle: {
            color: `${config.value.primaryColor}FF`,
            width: 2
          }
        }
      },
      yAxis: {
        type: 'value',
        axisLine: {
          show: false
        },
        axisLabel: {
          color: axisTextColor.value
        },
        splitLine: {
          show: true,
          lineStyle: {
            type: 'dashed',
            color: dotColor.value
          }
        }
      },
      tooltip: {
        trigger: 'axis',
        formatter(params) {
          const [firstElement] = params
          return `<div>
            <p class="tooltip-title">${firstElement.axisValueLabel}</p>
            <div class="content-panel"><span>${prop.seriesName}</span><span class="tooltip-value">${Number(firstElement.value).toLocaleString()}</span></div>
          </div>`
        },
        className: 'echarts-tooltip-diy'
      },
      graphic: {
        elements: graphicElements.value
      },
      series: [
        {
          data: chartsData.value,
          type: 'line',
          smooth: true,
          // symbol: 'circle',
          symbolSize: 12,
          emphasis: {
            focus: 'series',
            itemStyle: {
              borderWidth: 2
            }
          },
          lineStyle: {
            width: 3,
            color: new graphic.LinearGradient(0, 0, 1, 0, [
              {
                offset: 0,
                color: `${config.value.primaryColor}80`
              },
              {
                offset: 0.5,
                color: `${config.value.primaryColor}92`
              },
              {
                offset: 1,
                color: `${config.value.primaryColor}FF`
              }
            ])
          },
          showSymbol: false,
          areaStyle: {
            opacity: 0.8,
            color: new graphic.LinearGradient(0, 0, 0, 1, [
              {
                offset: 0,
                color: `${config.value.primaryColor}20`
              },
              {
                offset: 1,
                color: `${config.value.primaryColor}08`
              }
            ])
          }
        }
      ]
    }
  })
</script>

<style scoped lang="scss"></style>
