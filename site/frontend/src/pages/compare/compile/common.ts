import {BenchmarkFilter, StatComparison} from "../types";
import {TestCaseComparison} from "../data";

declare global {
  interface Window {
    __NON_RELEVANT_NO_NAME_FILTER_CACHE__?: any;
  }
}

export type CompileBenchmarkFilter = BenchmarkFilter;

export const defaultCompileFilter: CompileBenchmarkFilter = {
  name: null,
  regex: false,
  nonRelevant: false,
  showRawData: false,
};

export interface CompileBenchmarkComparison {
  benchmark: string;
  comparison: StatComparison;
}

export interface CompileTestCase {
  benchmark: string;
}

export function shouldShowTestCase(
  filter: BenchmarkFilter,
  comparison: TestCaseComparison<CompileTestCase>
) {
  const name = comparison.test_case.benchmark;
  const nameFilter = filter.name && filter.name.trim();
  if (!nameFilter) {
    return true
   } else if (filter.regex) {
    return name.match(nameFilter);;
  } else {
    return name.includes(nameFilter);
  }
}

export function testCaseKey(testCase: CompileTestCase): string {
  return testCase.benchmark;
}
