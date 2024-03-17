import {BenchmarkFilter, StatComparison} from "../types";
import {TestCaseComparison} from "../data";

export type CompileBenchmarkFilter = BenchmarkFilter;

export const defaultCompileFilter: CompileBenchmarkFilter = {
  name: null,
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
  const nameFiltered = !nameFilter || name.includes(nameFilter);

  return nameFiltered;
}

export function testCaseKey(testCase: CompileTestCase): string {
  return testCase.benchmark;
}
