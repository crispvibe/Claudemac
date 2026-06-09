import { u as Options } from "./types-BbnOeCab.mjs";

//#region src/rollup.d.ts
declare const rollup: (options: Options) => rollup.Plugin<any>[] | rollup.Plugin<any>;
//#endregion
export { rollup as default, rollup as "module.exports" };