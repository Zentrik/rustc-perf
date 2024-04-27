<script setup lang="ts">
import {TestCaseComparison} from "../../data";
import Tooltip from "../../tooltip.vue";
import {ArtifactDescription} from "../../types";
import {percentClass} from "../../shared";
import {CompileTestCase} from "../common";
import {computed} from "vue";
import {testCaseKey} from "../common";
import BenchmarkDetail from "./benchmark-detail.vue";
import Accordion from "../../../../components/accordion.vue";

const props = defineProps<{
  id: string;
  comparisons: TestCaseComparison<CompileTestCase>[];
  hasNonRelevant: boolean;
  showRawData: boolean;
  commitA: ArtifactDescription;
  commitB: ArtifactDescription;
  stat: string;
}>();

function prettifyRawNumber(number: number): string {
  return number.toLocaleString();
}

// Modify this when changing the number of columns in the table!
const columnCount = computed(() => {
  const base = 5;
  if (props.showRawData) {
    return base + 2;
  }
  return base;
});
const unit = computed(() => {
  // The DB stored wall-time data in nanoseconds for compile benchmarks, so it is
  // hardcoded here
  if (props.stat.split("-").pop() == "time") {
    return "ns";
  } else if (props.stat == "memory") {
    return "B";
  } else {
    return null;
  }
});
</script>

<template>
  <div class="bench-table" :id="id">
    <slot name="header"></slot>
    <div v-if="comparisons.length === 0" style="text-align: center">
      {{ hasNonRelevant ? "No relevant results" : "No results" }}
    </div>
    <table v-else class="benches compare">
      <thead>
        <tr>
          <th class="toggle-arrow"></th>
          <th>Benchmark</th>
          <th class="pct-change">% Change</th>
          <th class="narrow">
            Significance Threshold
            <Tooltip>
              The minimum % change that is considered significant. The higher
              the significance threshold, the noisier a test case is. You can
              see
              <a
                href="https://github.com/rust-lang/rustc-perf/blob/master/docs/comparison-analysis.md#what-makes-a-test-result-significant">
                here</a>
              how the significance threshold is calculated.
            </Tooltip>
          </th>
          <th class="narrow">
            Significance Factor
            <Tooltip>
              How much a particular result is over the significance threshold. A
              factor of 2.50x means the result is 2.5 times over the
              significance threshold.
            </Tooltip>
          </th>
          <th v-if="showRawData" class="raw-data">Before</th>
          <th v-if="showRawData" class="raw-data">After</th>
        </tr>
      </thead>
      <tbody>
        <template v-for="comparison in comparisons">
          <Accordion :id="testCaseKey(comparison.test_case)">
            <template v-slot:default>
              <td>
                <div class="benchmark_name">
                  {{ comparison.test_case.benchmark }}
                </div>
              </td>
              <td>
                <div class="numeric-aligned">
                  <span v-bind:class="percentClass(comparison.percent)">
                    {{ comparison.percent.toFixed(2) }}%
                  </span>
                </div>
              </td>
              <td class="narrow">
                <div class="numeric-aligned">
                  <div>
                    {{
                      comparison.comparison.significance_threshold
                        ? (
                          100 * comparison.comparison.significance_threshold
                        ).toFixed(2) + "%"
                        : "-"
                    }}
                  </div>
                </div>
              </td>
              <td class="narrow">
                <div class="numeric-aligned">
                  <div>
                    {{
                      comparison.comparison.significance_factor
                        ? comparison.comparison.significance_factor.toFixed(2) + "x"
                        : "-"
                    }}
                  </div>
                </div>
              </td>
              <td v-if="showRawData" class="numeric">
                <abbr :title="comparison.comparison.statistics[0].toString()">
                  {{ prettifyRawNumber(comparison.comparison.statistics[0]) }}{{ unit }}
                </abbr>
              </td>
              <td v-if="showRawData" class="numeric">
                <abbr :title="comparison.comparison.statistics[1].toString()">
                  {{ prettifyRawNumber(comparison.comparison.statistics[1]) }}{{ unit }}
                </abbr>
              </td>
            </template>
            <template v-slot:expanded>
              <td :colspan="columnCount">
                <BenchmarkDetail
                  :test-case="comparison.test_case"
                  :base-artifact="commitA"
                  :artifact="commitB"
                  :metric="stat"
                />
              </td>
            </template>
          </Accordion>
        </template>
      </tbody>
    </table>
  </div>
</template>

<style scoped lang="scss">
.benches {
  width: 100%;
  table-layout: fixed;
  font-size: medium;
  border-collapse: collapse;

  td,
  th {
    padding: 0.3em;
  }
}

.benches tbody::before {
  content: "";
  display: block;
  height: 10px;
}

.benches tbody:first-child th {
  text-align: center;
}

.benches tbody:not(:first-child) th {
  border-right: dotted 1px;
}

.benches {

  td,
  th {
    text-align: center;

    &.narrow, &.pct-change {
      word-wrap: break-word;
      width: 90px;
    }

    &.raw-data {
      width:90px;
      text-align: right;
    }
  }
}

.benches td {
  &>.numeric-aligned {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: right;

    &>div,
    &>span {
      width: 50px;
    }
  }

  &.numeric {
    text-align: right;
  }
}

.bench-table {
  margin-top: 10px;
}

.silent-link {
  color: inherit;
}

.benchmark_name {
  padding-left: 1rem;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

@media screen and (max-width: 400px) {
  .narrow {
    display: none;
  }
}
</style>
