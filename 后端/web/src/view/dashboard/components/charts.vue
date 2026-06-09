<template>
  <div class="">
    <div class="flex items-center justify-between mb-2">
      <div v-if="title" class="text-sm font-semibold tracking-tight text-black dark:text-white">
        {{ title }}
      </div>
      <slot v-else name="title" />
    </div>
    <div class="w-full relative">
      <div v-if="type !== 4">
        <div class="mt-4 text-3xl font-mono text-black dark:text-white">
          <el-statistic :value="metric.value || 0" />
        </div>
        <div class="mt-2 text-xs font-mono text-black/60 dark:text-white/60">
          {{ metric.changeText || '较昨日持平' }}
        </div>
      </div>
      <div class="absolute top-0 right-2 w-[50%] h-20">
        <charts-people-number v-if="type === 1" :data="metric.trend || []" height="100%" />
        <charts-people-number v-if="type === 2" :data="metric.trend || []" height="100%" />
        <charts-people-number v-if="type === 3" :data="metric.trend || []" height="100%" />
      </div>
      <charts-content-number
        v-if="type === 4"
        :data="trend.values || []"
        :labels="trend.labels || []"
        :series-name="trend.seriesName || '趋势值'"
        height="14rem"
      />
    </div>
  </div>
</template>

<script setup>
  import { defineAsyncComponent } from 'vue'

  const chartsPeopleNumber = defineAsyncComponent(() => import('./charts-people-numbers.vue'))
  const chartsContentNumber = defineAsyncComponent(() => import('./charts-content-numbers.vue'))

  defineProps({
    type: {
      type: Number,
      default: 1
    },
    title: {
      type: String,
      default: ''
    },
    metric: {
      type: Object,
      default: () => ({})
    },
    trend: {
      type: Object,
      default: () => ({})
    }
  })
</script>

<style scoped lang="scss"></style>
