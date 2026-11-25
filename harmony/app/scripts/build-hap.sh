#!/usr/bin/env bash
# Build the HarmonyOS client with the SDK bundled in DevEco Studio.
set -euo pipefail
DEVECO_STUDIO_HOME="${DEVECO_STUDIO_HOME:-/Applications/DevEco-Studio.app/Contents}"
HVIGOR="$DEVECO_STUDIO_HOME/tools/hvigor/bin/hvigorw"
if [ ! -x "$HVIGOR" ]; then
  echo "DevEco Studio 未找到；设置 DEVECO_STUDIO_HOME 指向应用的 Contents 目录。" >&2
  exit 2
fi
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_STUDIO_HOME/sdk}"
export JAVA_HOME="${JAVA_HOME:-$DEVECO_STUDIO_HOME/jbr/Contents/Home}"
export NODE_HOME="${NODE_HOME:-$DEVECO_STUDIO_HOME/tools/node}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [ ! -f build-profile.json5 ]; then
  cp build-profile.example.json5 build-profile.json5
fi
"$DEVECO_STUDIO_HOME/tools/ohpm/bin/ohpm" install --all
"$HVIGOR" --mode module -p product=default -p module=entry@default -p buildMode=debug \
  assembleHap --no-daemon
# An existing local signing profile can silently keep an older target and disable system materials.
"$NODE_HOME/bin/node" -e '
const { summary } = JSON.parse(require("node:fs").readFileSync("entry/build/default/outputs/default/pack.info", "utf8"));
if (!(summary.modules.find(m => m.distro.moduleName === "entry")?.apiVersion.target >= 26)) {
  console.error("请将本地 build-profile.json5 的 targetSdkVersion 更新到 26.0.0 或更高，保留原签名配置并重新构建。");
  process.exit(1);
}'
