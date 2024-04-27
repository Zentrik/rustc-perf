<script setup lang="ts">
import Toggle from "../toggle.vue";
import Tooltip from "../tooltip.vue";
import {ref, toRaw, watch} from "vue";
import {deepCopy} from "../../../utils/copy";
import {PREF_FILTERS_OPENED} from "../prefs";
import {createPersistedRef} from "../../../storage";
import {CompileBenchmarkFilter} from "./common";

const props = defineProps<{
  // When reset, set filter to this value
  defaultFilter: CompileBenchmarkFilter;
  // Initialize the filter with this value
  initialFilter: CompileBenchmarkFilter;
}>();
const emit = defineEmits<{
  (e: "change", filter: CompileBenchmarkFilter): void;
  (e: "export"): void;
}>();

function reset() {
  // We must not change the default filter
  filter.value = deepCopy(props.defaultFilter);
}

let filter = ref(deepCopy(props.initialFilter));
watch(
  filter,
  (newValue, _) => {
    emit("change", toRaw(newValue));
  },
  {deep: true}
);

const opened = createPersistedRef(PREF_FILTERS_OPENED);
</script>

<template>
  <fieldset class="collapsible-section">
    <Toggle :opened="opened" @change="(value) => (opened = value)">
      <template #label>Filters</template>
      <template #content>
        <div>
          <div class="section">
            <div class="section-heading">Filter</div>
            <input id="filter" type="text" v-model="filter.name" />
            <button
              class="regex-toggle"
              :class="{ active: filter.regex }"
              @click="filter.regex=!filter.regex"
            >
              .*
              <span class="regex-tooltiptext">
                Use Regular Expression
              </span>
            </button>
          </div>
          <div class="section">
            <div class="section-heading">
              <span>Show non-relevant results</span>
              <Tooltip>
                Whether to show test case results that are not relevant (i.e.,
                not significant or have a large enough magnitude). You can see
                <a
                  href="https://github.com/rust-lang/rustc-perf/blob/master/docs/comparison-analysis.md#how-is-relevance-of-a-test-run-summary-determined"
                >
                  here</a
                >
                how relevance is calculated.
              </Tooltip>
            </div>
            <input
              type="checkbox"
              v-model="filter.nonRelevant"
              style="margin-left: 20px"
            />
          </div>
          <div class="section">
            <div class="section-heading">
              <span>Display raw data</span>
              <Tooltip>Whether to display or not raw data columns.</Tooltip>
            </div>
            <input
              type="checkbox"
              v-model="filter.showRawData"
              style="margin-left: 20px"
            />
          </div>
          <button @click="reset" style="margin-right: 10px">
            Reset filters
          </button>
          <button
            @click="emit('export')"
            title="Download the currently filtered data as a Markdown table"
          >
            Export to Markdown
          </button>
        </div>
      </template>
    </Toggle>
  </fieldset>
</template>

<style scoped lang="scss">
.section-heading {
  font-size: 16px;
}

#filter {
  margin-left: 52px;
}

.states-list {
  display: flex;
  flex-direction: column;
  align-items: start;
  list-style: none;
  margin: 0;
  padding: 0;
}

.section-list-wrapper {
  flex-direction: column;
}

@media (min-width: 760px) {
  .states-list {
    justify-content: start;
    flex-direction: row;
    align-items: center;
    width: 80%;
  }

  .section-list-wrapper {
    flex-direction: row;
  }
}

.states-list > li {
  margin-right: 15px;
}

.label {
  font-weight: bold;
}

.regex-toggle {
  background-color: #ffffff;
  border: 1px solid #ccc;
  padding: 2px 6px;
  font-size: 12px;
  font-weight: bold;
  border-radius: 5px;
  position: relative;
  margin-left: 5px;
}

.regex-toggle.active {
  background-color: #bed6ed;
  border-color: #005fb8;
}

.regex-toggle:hover .regex-tooltiptext {
  visibility: visible;
  opacity: 1;
}

.regex-tooltiptext {
  width: 180px;
  visibility: hidden;
  color: white;
  background-color: #524d4d;
  text-align: center;
  padding: 5px;
  border-radius: 6px;

  position: absolute;
  bottom: 125%;
  margin-left: -60px;

  opacity: 0;
  transition: opacity 0.3s, visibility 0.3s;
}
@media screen and (max-width: 600px) {
  .regex-tooltiptext {
    width: 120px;
    margin-left: -180px;
  }
}
</style>
