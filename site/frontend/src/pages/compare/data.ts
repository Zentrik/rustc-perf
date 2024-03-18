import {BenchmarkFilter, StatComparison} from "./types";

export interface Summary {
  count: number;
  average: number;
  range: Array<number>;
}

export interface SummaryGroup {
  improvements: Summary;
  regressions: Summary;
  all: Summary;
}

export interface TestCaseComparison<Case> {
  test_case: Case;
  comparison: StatComparison;
  percent: number;
}

export function filterNonRelevant<Case>(
  filter: BenchmarkFilter,
  cases: TestCaseComparison<Case>[]
): TestCaseComparison<Case>[] {
  if (filter.nonRelevant) {
    return cases;
  }
  if (filter.name) {
    return cases.filter((c) => c.comparison.is_relevant);
  } else {
    if (!window.__NON_RELEVANT_NO_NAME_FILTER_CACHE__) {
      window.__NON_RELEVANT_NO_NAME_FILTER_CACHE__ = cases.filter(
        (c) => c.comparison.is_relevant
      );
    }
    return window.__NON_RELEVANT_NO_NAME_FILTER_CACHE__;
  }
}

/**
 * Computes summaries of improvements, regressions and all changes from the
 * given `testCases`.
 */
export function computeSummary<Case extends {benchmark: string}>(
  comparisons: TestCaseComparison<Case>[]
): SummaryGroup {
  let regressions: Summary = {
    count: 0,
    average: 0,
    range: [Infinity, 0],
  };

  let improvements: Summary = {
    count: 0,
    average: 0,
    range: [0, -Infinity],
  };

  let all: Summary = {
    count: comparisons.length,
    average: 0,
    range: [0, 0],
  };

  for (const testCase of comparisons) {
    if (testCase.percent < 0) {
      improvements.count++;
      improvements.range[0] = Math.min(improvements.range[0], testCase.percent);
      improvements.range[1] = Math.max(improvements.range[1], testCase.percent);
      improvements.average += testCase.percent;
    } else if (testCase.percent > 0) {
      regressions.count++;
      regressions.range[0] = Math.min(regressions.range[0], testCase.percent);
      regressions.range[1] = Math.max(regressions.range[1], testCase.percent);
      regressions.average += testCase.percent;
    }
    all.range[0] = Math.min(all.range[0], testCase.percent);
    all.range[1] = Math.max(all.range[1], testCase.percent);
    all.average += testCase.percent;
  }

  improvements.average = improvements.average / Math.max(1, improvements.count);
  regressions.average = regressions.average / Math.max(regressions.count);
  all.average = all.average / Math.max(1, all.count);

  if (improvements.count === 0) {
    improvements.range[1] = 0;
  }
  if (regressions.count === 0) {
    regressions.range[1] = 0;
  }

  return {
    improvements: improvements,
    regressions: regressions,
    all: all,
  };
}
