<script setup lang="ts">
import {loadBenchmarkInfo} from "../../api";
import AsOf from "../../components/as-of.vue";
import {
  createUrlWithAppendedParams,
  getUrlParams,
  navigateToUrlParams,
} from "../../utils/navigation";
import {Ref, ref} from "vue";
import {withLoading} from "../../utils/loading";
import {postMsgpack} from "../../utils/requests";
import {COMPARE_DATA_URL} from "../../urls";
import {CompareResponse, CompareSelector} from "./types";
import Header from "./header/header.vue";
import {computeSummary, filterNonRelevant, SummaryGroup} from "./data";
import DataSelector, {SelectionParams} from "./header/data-selector.vue";
import CompileBenchmarksPage from "./compile/compile-page.vue";
import {defaultCompileFilter as defaultCompileFilter} from "./compile/common";
import Tabs from "./tabs.vue";

function loadSelectorFromUrl(urlParams: Dict<string>): CompareSelector {
  const start = urlParams["start"] ?? "";
  const end = urlParams["end"] ?? "";
  const stat = urlParams["stat"] ?? "min-wall-time";
  return {
    start,
    end,
    stat,
  };
}

async function loadCompareData(
  selector: CompareSelector,
  loading: Ref<boolean>
) {
  const response = await withLoading(loading, async () => {
    const params = {
      start: selector.start,
      end: selector.end,
      stat: selector.stat,
    };
    return await postMsgpack<CompareResponse>(COMPARE_DATA_URL, params);
  });
  data.value = response;

  compileSummary.value = computeSummary(
    filterNonRelevant(defaultCompileFilter, response.compile_comparisons)
  );
}

function updateSelection(params: SelectionParams) {
  navigateToUrlParams(
    createUrlWithAppendedParams({
      start: params.start,
      end: params.end,
      stat: params.stat,
    }).searchParams
  );
}

const urlParams = getUrlParams();

// Include all relevant changes in the compile-time.
// We do not wrap these summaries in `computed`, because they should be loaded
// only once, after the compare data is downloaded.
const compileSummary: Ref<SummaryGroup | null> = ref(null);

const loading = ref(false);

const selector = loadSelectorFromUrl(urlParams);

const data: Ref<CompareResponse | null> = ref(null);
await loadCompareData(selector, loading);
const info = await loadBenchmarkInfo();
</script>

<template>
  <div>
    <Header :data="data" :selector="selector" />
    <DataSelector
      :start="selector.start"
      :end="selector.end"
      :stat="selector.stat"
      :info="info"
      @change="updateSelection"
    />
    <div v-if="loading">
      <p>Loading ...</p>
    </div>
    <div v-if="data !== null">
      <Tabs :compile-time-summary="compileSummary" />
      <CompileBenchmarksPage
        :data="data"
        :selector="selector"
        :benchmark-info="info"
      />
    </div>
  </div>
  <br />
  <AsOf :info="info" />
</template>
