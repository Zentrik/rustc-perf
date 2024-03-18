<script setup lang="ts">
const props = defineProps<{
  cases: number;
}>();
</script>

<template>
  <span>{{ props.cases }} </span>
</template>
