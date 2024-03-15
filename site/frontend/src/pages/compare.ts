import Compare from "./compare/page.vue";
import {createApp} from "vue";
import WithSuspense from "../components/with-suspense.vue";

const app = createApp(WithSuspense, {
  component: Compare,
});
// run export NODE_ENV=development and export __VUE_PROD_DEVTOOLS__=true to enable better profiling and uncomment below line
app.config.performance = true
app.mount("#app");
