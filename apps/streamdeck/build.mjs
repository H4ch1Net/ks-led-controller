import {build} from "esbuild";
await build({entryPoints:["src/plugin.ts"],outfile:"dev.kslight.controller.sdPlugin/bin/plugin.js",bundle:true,platform:"node",format:"esm",target:"node20",banner:{js:'import {createRequire} from "node:module"; const require = createRequire(import.meta.url);'}});
