import {CompileTestCase} from "./compile/common";
import {TestCaseComparison} from "./data";

export interface BenchmarkFilter {
  name: string | null;
  regex: boolean;
  nonRelevant: boolean;
  showRawData: boolean;
}

export interface CompareSelector {
  start: string;
  end: string;
  stat: string;
}

export type CommitType = "try" | "master";

export interface ArtifactDescription {
  commit: string;
  date: string | null;
  pr: number | null;
  type: CommitType;
  bootstrap: Dict<number>;
  bootstrap_total: number;
  component_sizes: Dict<number>;
}

export interface StatComparison {
  is_relevant: boolean;
  significance_threshold: number;
  significance_factor: number;
  statistics: [number, number];
}

export interface CompareResponse extends TestCaseComparison<CompileTestCase> {}
export interface CompareResponse {
  prev: string | null;
  next: string | null;
  is_contiguous: boolean;

  a: ArtifactDescription;
  b: ArtifactDescription;

  new_errors: Array<[string, string]>;

  compile_comparisons: TestCaseComparison<CompileTestCase>[];
}
