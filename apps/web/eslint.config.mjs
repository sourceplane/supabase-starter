// eslint-config-next 16 ships flat configs; the FlatCompat bridge the Next 15
// era template used trips over them (circular structure). This is what
// `create-next-app` generates for Next 16.
import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    // The template mounts next-themes with the usual
    // `useEffect(() => setMounted(true))` pattern; the rule that flags it
    // arrived with eslint-config-next 16 and the template is kept as written.
    rules: { "react-hooks/set-state-in-effect": "off" },
  },
  globalIgnores([".next/**", ".open-next/**", "out/**", "build/**", "next-env.d.ts"]),
]);

export default eslintConfig;
