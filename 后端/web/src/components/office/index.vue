<template>
  <div class="border border-solid border-gray-100 h-full w-full">
    <el-row>
      <div v-if="ext === 'docx'">
        <Docx v-model="fullFileURL" />
      </div>
      <div v-else-if="ext === 'pdf'">
        <Pdf v-model="fullFileURL" />
      </div>
      <div v-else-if="ext === 'xlsx'">
        <Excel v-model="fullFileURL" />
      </div>
      <div v-else-if="ext === 'image'">
        <el-image :src="fullFileURL" lazy />
      </div>
    </el-row>
  </div>
</template>
<script>
  export default {
    name: 'Office'
  }
</script>
<script setup>
  import { ref, watch, computed, defineAsyncComponent } from 'vue'

  const Docx = defineAsyncComponent(() => import('@/components/office/docx.vue'))
  const Pdf = defineAsyncComponent(() => import('@/components/office/pdf.vue'))
  const Excel = defineAsyncComponent(() => import('@/components/office/excel.vue'))

  const path = ref(import.meta.env.VITE_BASE_API)

  const model = defineModel({ type: String })

  const fileUrl = ref('')
  const ext = ref('')
  watch(
    () => model.value,
    (val) => {
	  const currentValue = val || ''
	  fileUrl.value = currentValue
	  const fileExt = currentValue.split('.')[1] || ''
	  const image = ['png', 'jpg', 'jpeg', 'gif']
	  ext.value = image.includes(fileExt?.toLowerCase()) ? 'image' : fileExt
	},
    { immediate: true }
  )
  const fullFileURL = computed(() => {
    return path.value + '/' + fileUrl.value
  })
</script>
