<script setup lang="tsx">
import ComparisonsTable from "./table/comparisons-table.vue";
import {TestCaseComparison} from "../data";
import {CompareResponse} from "../types";
import {CompileBenchmarkFilter, CompileTestCase} from "./common";

export interface BenchmarkProps {
  data: CompareResponse;
  testCases: TestCaseComparison<CompileTestCase>[];
  filter: CompileBenchmarkFilter;
  stat: string;
}

const props = defineProps<BenchmarkProps>();

const primaryCases = props.testCases;
const primaryHasNonRelevant = primaryCases.length > 0;
</script>

<template>
  <div style="margin-top: 15px">
    <div v-if="data.new_errors.length">
      <p><b>Newly broken benchmarks</b>:</p>
      <details v-for="[crate, error] in data.new_errors">
        <summary>{{ crate }}</summary>
        <pre>{{ error }}</pre>
      </details>
      <hr />
    </div>
    <ComparisonsTable
      id="primary-benchmarks"
      :comparisons="primaryCases"
      :has-non-relevant="primaryHasNonRelevant"
      :show-raw-data="filter.showRawData"
      :commit-a="data.a"
      :commit-b="data.b"
      :stat="stat"
    >
    </ComparisonsTable>
    <hr />
  </div>
</template>
