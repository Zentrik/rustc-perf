<script setup lang="ts">
/**
 * This component displays a select box that allows users to choose between three variants
 * of the `CachegrindCmd` component with a local `rustc-perf` profiling command.
 * Users can choose either to profile the baseline commit, the new commit, or to profile both
 * and display a diff.
 **/

import {CompileTestCase} from "../../common";
import Tooltip from "../../../tooltip.vue";
import CachegrindCmd from "./cachegrind-cmd.vue";

const props = defineProps<{
  testCase: CompileTestCase;
}>();
</script>

<template>
  <div class="title">
    Command for profiling locally
    <Tooltip>
      Note the index into `BaseBenchmarks.SUITE` may be subtly incorrect.
    </Tooltip>
  </div>

  <CachegrindCmd :test-case="props.testCase" />
</template>

<style scoped lang="scss">
.title {
  font-weight: bold;
}
</style>
