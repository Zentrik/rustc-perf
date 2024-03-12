<script setup lang="ts">
/**
 * This component displays a rustc-perf command for profiling a compile benchmark with Cachegrind.
 **/

import {CompileTestCase} from "../../common";
import {computed} from "vue";
import {onMounted} from 'vue';
import {normalizeProfile} from "./utils";

const props = defineProps<{
  commit: string;
  testCase: CompileTestCase;
  baselineCommit?: string;
}>();

const firstCommit = computed(() => {
  if (props.baselineCommit !== undefined) {
    return props.baselineCommit;
  } else {
    return props.commit;
  }
});

function normalizeScenario(scenario: string): string {
  if (scenario === "full") {
    return "Full";
  } else if (scenario === "incr-full") {
    return "IncrFull";
  } else if (scenario === "incr-unchanged") {
    return "IncrUnchanged";
  } else if (scenario.startsWith("incr-patched")) {
    return "IncrPatched";
  }
  return "<invalid scenario>";
}

function getsuite(benchmark: string): string {
  return benchmark.split('.', 1)[0];
}

function isNumeric(n) {
  return !isNaN(parseFloat(n)) && isFinite(n);
}

function normalizeBenchmark(benchmark: string): string {
  let i = benchmark.search("\\.\\(");
  if (i == -1) {
    let parts = benchmark.split('.');
    let result = [parts[0], parts[1]];
    if (parts.length > 2) {
      result.push(parts.slice(2).join('.'));
    }
    return result.map((x) => "\"" + x + "\"").join(", ");
  } else {
      let parts = benchmark.slice(0, i).split('.');
      let result = [parts[0]];
      if (parts.length > 1) {
        result.push(parts.slice(1).join('.'));
      }
      parts = result.map((x) => "\"" + x + "\"");

      let braces = 0;
      let start_idx = i + 2;
      let end_idx = i + 2;
      let split_tuple = [];

      while (end_idx < benchmark.length-1) {
        if (benchmark[end_idx] == "\{" || benchmark[end_idx] == "\(") {
          braces += 1;
        } else if (benchmark[end_idx] == "\}" || benchmark[end_idx] == "\)") {
          braces -= 1;
        } else if (benchmark[end_idx] == "," && braces == 0) {
          split_tuple.push(benchmark.slice(start_idx, end_idx));

          start_idx = end_idx + 1;
        }

        end_idx += 1;
      }
      split_tuple.push(benchmark.slice(start_idx, end_idx));

      // let split_tuple = benchmark.slice(i+2, benchmark.length-1).split(',');
      let quoted_tuple = split_tuple.map((x) => isNumeric(x) ? x.trimStart() : "\"" + x.trimStart() + "\"");
      let stringified_tuple = '\(' + quoted_tuple.join(", ").trimStart() + '\)';

      return parts.concat(stringified_tuple).join(", ");
  }
}

onMounted(() => {
  const codeBlocks = document.querySelectorAll('code');
  codeBlocks.forEach((codeBlock) => {
    codeBlock.addEventListener('click', (event) => {
      if (window.getSelection().toString() === '') {
        const range = document.createRange();
        range.selectNodeContents(codeBlock);
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
      }
    });
  });
});
</script>

<template>
  <pre><code tabindex="0">using BaseBenchmarks
BaseBenchmarks.load!("{{ getsuite(testCase.benchmark) }}")
res = run(BaseBenchmarks.SUITE[[{{ normalizeBenchmark(testCase.benchmark) }}]])</code></pre>
</template>

<style scoped lang="scss">
pre {
  background-color: #eeeeee;
  padding: 10px;
  padding-left: 15px;
  border-radius: 10px;         /* Rounded corners */
  white-space: pre-wrap;       /* Since CSS 2.1 */
  word-wrap: break-word;       /* Internet Explorer 5.5+ */
}
</style>
