<template>
  <div />
</template>

<script setup>
  import { useRouter } from 'vue-router'

  defineOptions({
    name: 'RouteRefreshBridge'
  })

  const router = useRouter()
  router.go(-1)
</script>
