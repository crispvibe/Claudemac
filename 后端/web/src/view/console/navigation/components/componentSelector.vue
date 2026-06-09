<template>
  <div class="w-full">
    <el-select
      v-model="activeComponent"
      placeholder="请选择页面组件"
      filterable
      clearable
      class="!w-full"
      @change="emitChange"
    >
      <el-option
        v-for="item in componentOptions"
        :key="item.value"
        :label="item.label"
        :value="item.value"
      />
    </el-select>
  </div>
</template>

<script setup>
  import { ref, watch } from 'vue'
  import { getComponentOptions, normalizeComponentId } from '@/utils/componentRegistry'

  const props = defineProps({
    component: {
      type: String,
      default: ''
    }
  })

  const emits = defineEmits(['change'])

  const componentOptions = getComponentOptions()
  const activeComponent = ref('')

  watch(
    () => props.component,
    (value) => {
      activeComponent.value = normalizeComponentId(value)
    },
    {
      immediate: true
    }
  )

  const emitChange = () => {
    emits('change', activeComponent.value || '')
  }
</script>

<style scoped lang="scss"></style>
