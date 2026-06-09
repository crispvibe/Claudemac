<template>
  <div class="nav-node-host h-full">
    <component
      :is="activeNavView"
      v-if="activeNavView"
      v-bind="activeNavProps"
    />
  </div>
</template>

<script setup>
  import NormalMode from './normalMode.vue'
  import HeadMode from './headMode.vue'
  import CombinationMode from './combinationMode.vue'
  import SidebarMode from './sidebarMode.vue'

  import { computed } from 'vue'
  import { storeToRefs } from 'pinia'
  import { useAppStore } from '@/pinia'

  const props = defineProps({
    mode: {
      type: String,
      default: 'normal'
    }
  })

  const appStore = useAppStore()
  const { config, device } = storeToRefs(appStore)

  const activeNavView = computed(() => {
    if (device.value === 'mobile') {
      return NormalMode
    }

    if (config.value.side_mode === 'head') {
      return HeadMode
    }

    if (config.value.side_mode === 'combination') {
      return CombinationMode
    }

    if (config.value.side_mode === 'sidebar') {
      return SidebarMode
    }

    if (config.value.side_mode === 'normal') {
      return NormalMode
    }

    return null
  })

  const activeNavProps = computed(() => {
    if (activeNavView.value === CombinationMode) {
      return {
        mode: props.mode
      }
    }

    return {}
  })
</script>
