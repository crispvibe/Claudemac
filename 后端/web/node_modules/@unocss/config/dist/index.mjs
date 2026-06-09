import fs from "node:fs";
import { dirname, resolve } from "node:path";
import process from "node:process";
import { createConfigLoader } from "unconfig";

//#region src/index.ts
async function loadConfig(cwd = process.cwd(), configOrPath = cwd, extraConfigSources = [], defaults = {}) {
	let inlineConfig = {};
	if (typeof configOrPath !== "string") {
		inlineConfig = configOrPath;
		if (inlineConfig.configFile === false) return {
			config: inlineConfig,
			sources: []
		};
		else configOrPath = inlineConfig.configFile || process.cwd();
	}
	const resolved = resolve(configOrPath);
	let isFile = false;
	if (fs.existsSync(resolved) && fs.statSync(resolved).isFile()) {
		isFile = true;
		cwd = dirname(resolved);
	}
	const result = await createConfigLoader({
		sources: isFile ? [{
			files: resolved,
			extensions: []
		}] : [{ files: ["unocss.config", "uno.config"] }, ...extraConfigSources],
		cwd,
		defaults: inlineConfig
	}).load();
	result.config = Object.assign(defaults, inlineConfig, result.config ?? {});
	if (result.config.configDeps) result.sources = [...result.sources, ...result.config.configDeps.map((i) => resolve(cwd, i))];
	return result;
}
/**
* Create a factory function that returns a config loader that recovers from errors.
*
* When it fails to load the config, it will return the last successfully loaded config.
*
* Mainly used for dev-time where users might have a broken config in between changes.
*/
function createRecoveryConfigLoader() {
	let lastResolved;
	return async (cwd = process.cwd(), configOrPath = cwd, extraConfigSources = [], defaults = {}) => {
		try {
			const config = await loadConfig(cwd, configOrPath, extraConfigSources, defaults);
			lastResolved = config;
			return config;
		} catch (e) {
			if (lastResolved) {
				console.error(e);
				return lastResolved;
			}
			throw e;
		}
	};
}

//#endregion
export { createRecoveryConfigLoader, loadConfig };