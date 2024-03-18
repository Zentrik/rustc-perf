<script setup lang="ts">
import MetricSelector from "../metric-selector.vue";
import Filters from "./filters.vue";
import OverallSummary from "../summary/overall-summary.vue";
import Benchmarks from "./benchmarks.vue";
import { CompareResponse, CompareSelector } from "../types";
import { computed, ref } from "vue";
import { changeUrl, getUrlParams } from "../../../utils/navigation";
import { exportToMarkdown } from "./export";
import { computeSummary, filterNonRelevant } from "../data";
import {
  CompileBenchmarkFilter,
  shouldShowTestCase,
  defaultCompileFilter,
} from "./common";
import { BenchmarkInfo } from "../../../api";
import { importantCompileMetrics } from "../metrics";
import { getBoolOrDefault } from "../shared";

const props = defineProps<{
  data: CompareResponse;
  selector: CompareSelector;
  benchmarkInfo: BenchmarkInfo;
}>();

function loadFilterFromUrl(
  urlParams: Dict<string>,
  defaultFilter: CompileBenchmarkFilter
): CompileBenchmarkFilter {
  return {
    name: urlParams["name"] ?? defaultFilter.name,
    nonRelevant: getBoolOrDefault(
      urlParams,
      "nonRelevant",
      defaultFilter.nonRelevant
    ),
    showRawData: getBoolOrDefault(
      urlParams,
      "showRawData",
      defaultFilter.showRawData
    ),
  };
}

/**
 * Stores the given filter parameters into URL, so that the current "view" can be shared with
 * others easily.
 */
function storeFilterToUrl(
  filter: CompileBenchmarkFilter,
  defaultFilter: CompileBenchmarkFilter,
  urlParams: Dict<string>
) {
  function storeOrReset<T extends boolean | string>(
    name: string,
    value: T,
    defaultValue: T
  ) {
    if (value === defaultValue) {
      if (urlParams.hasOwnProperty(name)) {
        delete urlParams[name];
      }
    } else {
      urlParams[name] = value.toString();
    }
  }

  storeOrReset("name", filter.name || null, defaultFilter.name);
  storeOrReset("nonRelevant", filter.nonRelevant, defaultFilter.nonRelevant);
  storeOrReset("showRawData", filter.showRawData, defaultFilter.showRawData);

  changeUrl(urlParams);
}

function updateFilter(newFilter: CompileBenchmarkFilter) {
  storeFilterToUrl(newFilter, defaultCompileFilter, getUrlParams());
  filter.value = newFilter;
  refreshQuickLinks();
}

/**
 * When the filter changes, the URL is updated.
 * After that happens, we want to re-render the quick links component, because
 * it contains links that are "relative" to the current URL. Changing this
 * key ref will cause it to be re-rendered.
 */
function refreshQuickLinks() {
  quickLinksKey.value += 1;
}

const urlParams = getUrlParams();

const quickLinksKey = ref(0);
const filter = ref(loadFilterFromUrl(urlParams, defaultCompileFilter));

function exportData() {
  exportToMarkdown(comparisons.value);
}

// We also computed this in page.vue for the summary, could reuse
const allComparisons = computed(() => {
  if (filter.value.name) {
    return props.data.compile_comparisons.filter((tc) =>
      shouldShowTestCase(filter.value, tc)
    );
  } else {
    return props.data.compile_comparisons;
  }
});
const comparisons = computed(() =>
  filterNonRelevant(filter.value, allComparisons.value)
);
const filteredSummary = computed(() => computeSummary(comparisons.value));
</script>

<template>
  <MetricSelector :key="quickLinksKey" :quick-links="importantCompileMetrics" :selected-metric="selector.stat"
    :metrics="benchmarkInfo.compile_metrics" />
  <Filters :defaultFilter="defaultCompileFilter" :initialFilter="filter" @change="updateFilter" @export="exportData" />
  <OverallSummary :summary="filteredSummary" />
  <Benchmarks :data="data" :test-cases="comparisons" :filter="filter" :stat="selector.stat"></Benchmarks>
</template>
