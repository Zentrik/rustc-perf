<script setup lang="tsx">
import {h, ref, Ref} from "vue";
import {CompareResponse, Tab} from "./types";
import {
  diffClass,
  formatPercentChange,
  formatSize,
  percentClass,
} from "./shared";
import {SummaryGroup} from "./data";
import SummaryPercentValue from "./summary/percent-value.vue";
import SummaryRange from "./summary/range.vue";
import TabComponent from "../../components/tab.vue";

const props = withDefaults(
  defineProps<{
    data: CompareResponse;
    compileTimeSummary: SummaryGroup;
    initialTab?: Tab;
  }>(),
  {
    initialTab: Tab.CompileTime,
  }
);
const emit = defineEmits<{
  (e: "changeTab", tab: Tab): void;
}>();

function changeTab(tab: Tab) {
  activeTab.value = tab;
  emit("changeTab", tab);
}

function SummaryTable({summary}: {summary: SummaryGroup}) {
  const valid = summary.all.count > 0;
  if (valid) {
    return (
      <div class="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Range</th>
              <th style="padding-left: 1.4rem">Mean</th>
            </tr>
          </thead>
          <thead>
            <tr>
              <td>
                <SummaryRange range={summary.all.range} />
              </td>
              <td style="padding-left: 1.2rem">
                <SummaryPercentValue
                  class={percentClass(summary.all.average)}
                  value={summary.all.average}
                />
              </td>
            </tr>
          </thead>
        </table>
      </div>
    );
  }
  return <div>No results</div>;
}

function formatArtifactSize(size: number): string {
  if (size === 0) {
    return "???";
  }
  return formatSize(size);
}

const totalSizeA = Object.values(props.data.a.component_sizes).reduce(
  (a, b) => a + b,
  0
);
const totalSizeB = Object.values(props.data.b.component_sizes).reduce(
  (a, b) => a + b,
  0
);
const sizesAvailable = totalSizeA > 0 || totalSizeB > 0;
const bothSizesAvailable = totalSizeA > 0 && totalSizeB > 0;

const activeTab: Ref<Tab> = ref(props.initialTab);
</script>

<template>
  <div class="wrapper">
    <TabComponent
      tooltip="Benchmarks: measure how long does it take to execute various benchmarks."
      title="Benchmarks"
      :selected="activeTab === Tab.CompileTime"
      @click="changeTab(Tab.CompileTime)"
    >
      <template v-slot:summary>
        <SummaryTable :summary="compileTimeSummary" />
      </template>
    </TabComponent>
    <TabComponent
      tooltip="Artifact size: sizes of individual components of the two artifacts."
      title="Artifact size"
      v-if="sizesAvailable"
      :selected="activeTab === Tab.ArtifactSize"
      @click="changeTab(Tab.ArtifactSize)"
    >
      <template v-slot:summary>
        <div>
          {{ formatArtifactSize(totalSizeA) }} ->
          {{ formatArtifactSize(totalSizeB) }}
        </div>
        <div
          v-if="bothSizesAvailable"
          :class="diffClass(totalSizeB - totalSizeA)"
        >
          {{ totalSizeB < totalSizeA ? "-" : ""
          }}{{ formatSize(Math.abs(totalSizeB - totalSizeA)) }} ({{
            formatPercentChange(totalSizeA, totalSizeB)
          }})
        </div>
      </template>
    </TabComponent>
  </div>
</template>

<style scoped lang="scss">
.wrapper {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 20px 0;

  @media (min-width: 600px) {
    justify-content: center;
    flex-direction: row;
    align-items: normal;
  }
}

.table-wrapper {
  table {
    width: 100%;
    table-layout: auto;
  }

  th {
    font-weight: normal;
  }
}
</style>
