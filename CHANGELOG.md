# Changelog

## 2.1.0

- Added `coral1.6-prompt` Modelfile and `/promptup` refinement skill.
- Added `/work`, `/critic`, `/verify`, and `/decision` skills.
- Added visible skill pipelines and standardized ASCII activity loaders.
- Added background incremental remembering using only the newest chat turn.
- Added serialized background Brain jobs and atomic memory writes.
- Added the built-in fully isolated `sandbox` project.
- Added temporary, non-persistent `/document` behavior in Sandbox.
- Added official `AKRO_VISIBLE_MODELS` support with all-model fallback when unset.
- Fixed finished streamed responses not being repainted through Glow immediately.
- Added V2.1 upgrade instructions and helper-model documentation.

## 2.0.0

- Initial modular Akro V2 release.
