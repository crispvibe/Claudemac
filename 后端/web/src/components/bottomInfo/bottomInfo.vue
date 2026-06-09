<template>
  <div
    class="flex flex-col md:flex-row gap-2 items-center text-sm text-slate-700 dark:text-slate-500 justify-center py-2"
  >
    <div class="text-center text-[#94a3b8]">
      <span>Copyright &copy; 2026 禾屿科技 All Rights Reserved.</span>
    </div>
    <slot />
  </div>
</template>
<script setup>
  defineOptions({
    name: 'BottomInfo'
  })
</script>
