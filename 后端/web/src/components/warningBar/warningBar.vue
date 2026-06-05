<template>
  <div
    class="px-4 py-3 flex items-center rounded-2xl mt-2 bg-[#fffbeb] gap-2 mb-4 text-[#d97706] dark:bg-amber-700 dark:text-gray-200 border border-amber-500/10 shadow-[0_4px_16px_rgba(217,119,6,0.06)] box-border"
    :class="href && 'cursor-pointer'"
    @click="open"
  >
    <el-icon class="text-xl">
      <warning-filled />
    </el-icon>
    <span>
      {{ title }}
    </span>
  </div>
</template>
<script setup>
  import { WarningFilled } from '@element-plus/icons-vue'
  const prop = defineProps({
    title: {
      type: String,
      default: ''
    },
    href: {
      type: String,
      default: ''
    }
  })

  const isLocalPath = (value) => typeof value === 'string' && value.startsWith('/') && !value.startsWith('//')

  const open = () => {
    if (prop.href && isLocalPath(prop.href)) {
      window.open(prop.href)
    }
  }
</script>
