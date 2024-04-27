<script setup lang="tsx">
import {h} from "vue";
import {percentClass} from "./shared";
import {SummaryGroup} from "./data";
import SummaryPercentValue from "./summary/percent-value.vue";
import SummaryRange from "./summary/range.vue";
import TabComponent from "../../components/tab.vue";

const props = defineProps<{
  compileTimeSummary: SummaryGroup;
}>();

function SummaryTable({summary}: {summary: SummaryGroup}) {
  const valid = summary.all.count > 0;
  if (valid) {
    return (
      <div class="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>Range</th>
              <th>Mean</th>
            </tr>
          </thead>
          <thead>
            <tr>
              <td>
                <SummaryRange range={summary.all.range} />
              </td>
              <td>
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
</script>

<template>
  <div class="wrapper">
    <TabComponent
      tooltip="Benchmarks: measure how long does it take to execute various benchmarks."
      title="Benchmarks"
    >
      <template v-slot:summary>
        <SummaryTable :summary="compileTimeSummary" />
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
