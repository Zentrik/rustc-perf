export interface MetricDescription {
  label: string;
  metric: string;
  description: string;
}

const sharedMetrics: MetricDescription[] = [
  {
    label: "Min wall time",
    metric: "min-wall-time",
    description: "Minimum wall time (ns)",
  },
  {
    label: "Median wall time",
    metric: "median-wall-time",
    description: "Median wall time (ns)",
  },
  {
    label: "Mean wall time",
    metric: "mean-wall-time",
    description: "Mean wall time (ns)",
  },
  {
    label: "Allocations",
    metric: "allocs",
    description: "Number of heap allocations",
  },
  {
    label: "Memory",
    metric: "memory",
    description: "Size of heap allocations (bytes)",
  },
];

export const importantCompileMetrics: MetricDescription[] = [
  ...sharedMetrics,
];

export const importantRuntimeMetrics: MetricDescription[] = [...sharedMetrics];
