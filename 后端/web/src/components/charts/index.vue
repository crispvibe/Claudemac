<template>
  <VCharts
    v-if="renderChart"
    :option="options"
    :autoresize="autoResize"
    :style="{ width, height }"
  />
</template>

<script setup>
  import { ref, nextTick, defineAsyncComponent } from 'vue'
  import { useWindowResize } from '@/hooks/use-resize'

  const VCharts = defineAsyncComponent(() => import('./runtime.js'))

  defineProps({
    options: {
      type: Object,
      default() {
        return {}
      }
    },
    autoResize: {
      type: Boolean,
      default: true
    },
    width: {
      type: String,
      default: '100%'
    },
    height: {
      type: String,
      default: '100%'
    }
  })
  const renderChart = ref(false)
  nextTick(() => {
    renderChart.value = true
  })
  useWindowResize(() => {
    renderChart.value = false
    nextTick(() => {
      renderChart.value = true
    })
  })
</script>

<style scoped lang="less"></style>
