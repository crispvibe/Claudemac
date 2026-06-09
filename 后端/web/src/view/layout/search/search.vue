<template>
  <div class="utility-toggle-bar items-center">
    <div
      class="shellGlyph shellGlyph-refresh"
      :class="[reload ? 'reloading' : '']"
      @click="handleReload"
    />
    <ViewportToggle class="utility-toggle-bar__viewport" />
    <el-switch
      v-model="isDark"
      :active-action-icon="Moon"
      :inactive-action-icon="Sunny"
      @change="handleDarkSwitch"
    />
  </div>
</template>

<script setup>
  import ViewportToggle from '@/view/layout/screenfull/index.vue'
  import { emitter } from '@/utils/event-bus.js'
  import { Sunny, Moon } from '@element-plus/icons-vue'
  import { ref, watchEffect } from 'vue'

  defineOptions({
    name: 'UtilityToggleBar'
  })
  const isDark = ref(localStorage.getItem('isDark') !== 'false')

  watchEffect(() => {
    if (isDark.value) {
      document.documentElement.classList.add('dark')
      localStorage.setItem('isDark', true)
    } else {
      document.documentElement.classList.remove('dark')
      localStorage.setItem('isDark', false)
    }
  })
  const reload = ref(false)
  const handleReload = () => {
    reload.value = true
    emitter.emit('reload')
    setTimeout(() => {
      reload.value = false
    }, 500)
  }

  const handleDarkSwitch = (e) => {
    isDark.value = e
  }
</script>
<style scoped lang="scss">
  .utility-toggle-bar {
    @apply inline-flex overflow-hidden text-center gap-5 mr-5 text-black dark:text-gray-100;
    div {
      @apply cursor-pointer;
    }
    .el-input__inner {
      @apply border-b border-solid border-gray-300;
    }
    .el-dropdown-link {
      @apply cursor-pointer;
    }
  }

  .reload {
    font-size: 18px;
  }

  .reloading {
    animation: turn 0.5s linear infinite;
  }

  @keyframes turn {
    0% {
      transform: rotate(0deg);
    }

    25% {
      transform: rotate(90deg);
    }

    50% {
      transform: rotate(180deg);
    }

    75% {
      transform: rotate(270deg);
    }

    100% {
      transform: rotate(360deg);
    }
  }
</style>
