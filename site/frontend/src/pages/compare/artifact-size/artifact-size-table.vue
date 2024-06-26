<script setup lang="ts">
import {ArtifactDescription} from "../types";
import {diffClass, formatPercentChange, formatSize} from "../shared";
import Tooltip from "../tooltip.vue";

const props = defineProps<{
  a: ArtifactDescription;
  b: ArtifactDescription;
}>();

interface ComponentSize {
  name: string;
  before: number;
  after: number;
}

const allComponents: ComponentSize[] = [
  ...new Set([
    ...Object.keys(props.a.component_sizes),
    ...Object.keys(props.b.component_sizes),
  ]),
].map((name) => {
  const before = props.a.component_sizes[name] ?? 0;
  const after = props.b.component_sizes[name] ?? 0;
  return {
    name,
    before,
    after,
  };
});

// Sort binaries first, libraries later. Then within each category, sort alphabetically.
const components = allComponents.sort((a, b) => {
  const aLib = isLibrary(a.name);
  const bLib = isLibrary(b.name);
  if (aLib && !bLib) {
    return 1;
  } else if (!aLib && bLib) {
    return -1;
  } else {
    return a.name.localeCompare(b.name);
  }
});

function isLibrary(component: string): boolean {
  return component.startsWith("lib");
}

function formatValue(value: number): string {
  if (value === 0) {
    return "-";
  }
  return formatSize(value);
}

function formatChangeTitle(a: number, b: number): string {
  return (b - a).toLocaleString();
}

function formatTitle(value: number): string {
  if (value === 0) {
    return "Missing value";
  }
  return value.toLocaleString();
}

function formatChange(a: number, b: number): string {
  const diff = b - a;
  const formatted = formatSize(Math.abs(diff));
  if (diff < 0) {
    return `-${formatted}`;
  }
  return formatted;
}

function getClass(a: number, b: number): string {
  if (a === b) {
    return "";
  }
  return diffClass(b - a);
}

function generateTitle(component: string): string {
  if (component === "julia") {
    return `Executable of Julia.`;
  } else if (component === "sys.so") {
    return "A shared library containing the preparsed system image containing the contents of the `Base` module.";
  } else if (component === "libjulia.so") {
    return `Shared library of Julia...`;
  } else if (component === "libLLVM") {
    return `Shared library of the LLVM codegen backend. It is used by librustc_driver.so.`;
    return ""; // Unknown component
  }
}
</script>

<template>
  <div class="category-title">Artifact component sizes</div>
  <div class="wrapper">
    <table>
      <thead>
        <tr>
          <th>Component</th>
          <th>Kind</th>
          <th class="aligned-header">Before</th>
          <th class="aligned-header">After</th>
          <th class="aligned-header">Change</th>
          <th class="aligned-header">% Change</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="component in components">
          <td class="component">
            {{ component.name }}
            <Tooltip>{{ generateTitle(component.name) }}</Tooltip>
          </td>
          <td>
            {{ isLibrary(component.name) ? "Library" : "Binary" }}
          </td>
          <td>
            <div class="aligned" :title="formatTitle(component.before)">
              {{ formatValue(component.before) }}
            </div>
          </td>
          <td>
            <div class="aligned" :title="formatTitle(component.after)">
              {{ formatValue(component.after) }}
            </div>
          </td>
          <td :class="getClass(component.before, component.after)">
            <div
              class="aligned"
              :title="formatChangeTitle(component.before, component.after)"
            >
              {{ formatChange(component.before, component.after) }}
            </div>
          </td>
          <td :class="getClass(component.before, component.after)">
            <div class="aligned">
              {{ formatPercentChange(component.before, component.after) }}
            </div>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>

<style scoped lang="scss">
.wrapper {
  display: flex;
  justify-content: center;
}
table {
  table-layout: fixed;
  margin-top: 10px;

  td,
  th {
    text-align: center;
    padding: 0.3em;
  }

  .component {
    word-break: break-word;
  }

  .aligned {
    text-align: right;

    @media (min-width: 600px) {
      width: 120px;
    }
  }
  .aligned-header {
    text-align: right;
  }
}
</style>
