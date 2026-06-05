<template>
  <div
    class="rounded-[20px] bg-white transition-all duration-300 shadow-[0_12px_32px_-12px_rgba(0,0,0,0.06)] hover:shadow-[0_16px_40px_-16px_rgba(0,0,0,0.08)] border border-gray-100 box-border text-[#1d1d1f]"
    :class="[customClass || '', withoutPadding ? 'p-0' : 'p-6']"
  >
    <div v-if="title" class="flex justify-between items-center mb-1">
      <div class="text-[16px] font-semibold tracking-tight text-[#1d1d1f]">
        {{ title }}
      </div>
      <div
        v-if="showAction"
        class="text-[13px] font-medium text-[#86868b] hover:text-[#1d1d1f] transition-colors cursor-pointer px-2 py-1 bg-gray-50 rounded-full hover:bg-gray-100"
      >
        查看更多
      </div>
    </div>
    <div :class="title ? 'mt-3' : ''">
      <slot />
    </div>
  </div>
</template>

<script setup>
  defineProps({
    title: {
      type: String,
      default: ''
    },
    showAction: {
      type: Boolean,
      default: false
    },
    customClass: {
      type: String,
      default: ''
    },
    withoutPadding: {
      type: Boolean,
      default: false
    }
  })
</script>

<style scoped lang="scss"></style>
