<template>
  <span class="headerAvatar">
    <template v-if="picType === 'avatar'">
      <el-avatar v-if="userStore.userInfo.headerImg" :size="30" :src="avatar" />
      <el-avatar v-else :size="30" class="avatar-placeholder">{{ placeholderText }}</el-avatar>
    </template>
    <template v-if="picType === 'img'">
      <img v-if="userStore.userInfo.headerImg" :src="avatar" class="avatar" />
      <div v-else class="avatar avatar-placeholder image-placeholder">{{ placeholderText }}</div>
    </template>
    <template v-if="picType === 'file'">
      <el-image
        :src="file"
        class="file"
        :preview-src-list="previewSrcList"
        :preview-teleported="true"
      />
    </template>
  </span>
</template>

<script setup>
  import { useUserStore } from '@/pinia/modules/user'
  import { computed, ref } from 'vue'

  defineOptions({
    name: 'CustomPic'
  })

  const props = defineProps({
    picType: {
      type: String,
      required: false,
      default: 'avatar'
    },
    picSrc: {
      type: String,
      required: false,
      default: ''
    },
    preview: {
      type: Boolean,
      default: false
    }
  })

  const path = ref(import.meta.env.VITE_BASE_API + '/')

  const userStore = useUserStore()
  const placeholderText = computed(() => {
    const userName = userStore.userInfo.userName || 'HY'
    return userName.slice(0, 1).toUpperCase()
  })

  const isExternalResource = (value) => typeof value === 'string' && /^https?:\/\//i.test(value)

  const avatar = computed(() => {
    if (props.picSrc === '') {
      if (
        userStore.userInfo.headerImg !== '' &&
        !isExternalResource(userStore.userInfo.headerImg)
      ) {
        return path.value + userStore.userInfo.headerImg
      }
      return ''
    } else {
      if (props.picSrc !== '' && !isExternalResource(props.picSrc)) {
        return path.value + props.picSrc
      }
      return ''
    }
  })
  const file = computed(() => {
    if (props.picSrc && !isExternalResource(props.picSrc)) {
      return path.value + props.picSrc
    }
    return ''
  })
  const previewSrcList = computed(() => (props.preview ? [file.value] : []))
</script>

<style scoped>
  .headerAvatar {
    display: flex;
    justify-content: center;
    align-items: center;
    margin-right: 8px;
  }
  .file {
    width: 80px;
    height: 80px;
    position: relative;
  }
  .avatar-placeholder {
    background: linear-gradient(135deg, #0f172a, #334155);
    color: #f8fafc;
    font-weight: 600;
  }
  .image-placeholder {
    width: 30px;
    height: 30px;
    border-radius: 9999px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
  }
</style>
