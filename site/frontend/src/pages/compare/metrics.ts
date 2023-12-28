export interface MetricDescription {
  label: string;
  metric: string;
  description: string;
}

const sharedMetrics: MetricDescription[] = [
  {
    label: "Min wall time",
    metric: "min-wall-time",
    description: "Minimum wall time",
  },
];

export const importantCompileMetrics: MetricDescription[] = [
  ...sharedMetrics,
];

export const importantRuntimeMetrics: MetricDescription[] = [...sharedMetrics];
