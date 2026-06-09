<template>
  <div @click="clickFull">
    <div v-if="isShow" class="shellGlyph shellGlyph-fullscreen-expand" />
    <div v-else class="shellGlyph shellGlyph-fullscreen-shrink" />
  </div>
</template>

<script setup>
  import screenfull from 'screenfull' // 引入screenfull
  import { onMounted, onUnmounted, ref } from 'vue'

  defineOptions({
    name: 'ViewportToggle'
  })

  defineProps({
    width: {
      type: Number,
      default: 22
    },
    height: {
      type: Number,
      default: 22
    },
    fill: {
      type: String,
      default: '#48576a'
    }
  })

  onMounted(() => {
    if (screenfull.isEnabled) {
      screenfull.on('change', changeFullShow)
    }
  })

  onUnmounted(() => {
    screenfull.off('change')
  })

  const clickFull = () => {
    if (screenfull.isEnabled) {
      screenfull.toggle()
    }
  }

  const isShow = ref(true)
  const changeFullShow = () => {
    isShow.value = !screenfull.isFullscreen
  }
</script>

<style scoped lang="scss">
  .viewport-toggle-icon {
    width: 16px;
    height: 16px;
    cursor: pointer;
    vertical-align: middle;
    margin-right: 32px;
    fill: rgba(0, 0, 0, 0.45);
  }
</style>
