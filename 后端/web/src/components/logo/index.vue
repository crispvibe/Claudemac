<script setup>
import { computed } from 'vue'

const props = defineProps({
  // logo 尺寸，单位为:rem
  size: {
    type: Number,
    default: 2
  }
})

// 直接用 16px 作为默认的基准大小
const SPACING = 16
const logoSize = computed(() => ({
    width: `${props.size * SPACING}px`,
    height: `${props.size * SPACING}px`,
  }))
</script>

<template>
  <div
    class="rounded-2xl border border-slate-200 dark:border-slate-700 bg-gradient-to-br from-slate-900 to-slate-700 dark:from-slate-100 dark:to-slate-300 text-white dark:text-slate-900 flex items-center justify-center font-semibold tracking-[0.2em] shadow-sm"
    :style="logoSize"
  >
    HY
  </div>
</template>
