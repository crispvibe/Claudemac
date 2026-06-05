<template>
  <el-scrollbar>
    <div
      v-for="(item, index) in notices"
      :key="index"
      class="flex items-center gap-3 py-1"
    >
      <div
        class="shrink-0 rounded-full border border-black/10 px-2 py-0.5 text-[11px] leading-4 text-black/70 dark:border-white/10 dark:text-white/70"
      >
        {{ item.levelTitle }}
      </div>
      <el-tooltip effect="light" :content="item.title" placement="top">
        <div class="min-w-0 flex-1 text-xs text-black/70 dark:text-white/70 line-clamp-1">
          {{ item.title }}
        </div>
      </el-tooltip>
      <div class="shrink-0 text-[11px] text-black/40 dark:text-white/40">{{ item.time }}</div>
    </div>
  </el-scrollbar>
</template>

<script setup>
  defineProps({
    notices: {
      type: Array,
      default: () => []
    }
  })
</script>

<style scoped lang="scss"></style>
