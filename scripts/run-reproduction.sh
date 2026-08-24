#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
next_version="${1:-16.3.2}"
bundler="${REPRO_BUNDLER:-turbopack}"
memory_limit="${MEMORY_LIMIT:-4g}"
cpu_limit="${CPU_LIMIT:-2}"
build_timeout_seconds="${BUILD_TIMEOUT_SECONDS:-180}"
result_name="${next_version//[^a-zA-Z0-9._-]/-}-${bundler}"
result_directory="${repository_root}/results/${result_name}"
runtime_image="oven/bun:1.4.0"
next_runtime="bun"
if [[ "${bundler}" == "webpack" ]]; then
  runtime_image="node:24-bookworm-slim"
  next_runtime="node"
fi

mkdir -p "${result_directory}"
rm -f "${result_directory}/build.log" "${result_directory}/memory.csv" "${result_directory}/memory.events"

set +e
docker run --rm \
  --cpus="${cpu_limit}" \
  --memory="${memory_limit}" \
  --memory-swap="${memory_limit}" \
  --mount "type=bind,source=${repository_root},target=/source,readonly" \
  --mount "type=bind,source=${result_directory},target=/results" \
  --mount "type=volume,source=next-turbopack-memory-bun-cache,target=/root/.bun/install/cache" \
  --env "NEXT_VERSION=${next_version}" \
  --env "REPRO_ROUTES=${REPRO_ROUTES:-100}" \
  --env "REPRO_COMPONENTS_PER_ROUTE=${REPRO_COMPONENTS_PER_ROUTE:-64}" \
  --env "REPRO_ROWS_PER_COMPONENT=${REPRO_ROWS_PER_COMPONENT:-96}" \
  --env "REPRO_REACT_COMPILER=${REPRO_REACT_COMPILER:-true}" \
  --env "REPRO_BUNDLER=${bundler}" \
  --env "NEXT_RUNTIME=${next_runtime}" \
  --env "NEXT_EXPERIMENTAL_CPUS=${NEXT_EXPERIMENTAL_CPUS:-}" \
  --env "BUILD_TIMEOUT_SECONDS=${build_timeout_seconds}" \
  --env NEXT_TELEMETRY_DISABLED=1 \
  "${runtime_image}" \
  bash -lc '
    set -euo pipefail
    cp -R /source/. /work
    cd /work
    if [[ "$REPRO_BUNDLER" == "webpack" ]]; then
      if [[ "$NEXT_VERSION" != "16.3.2" ]]; then
        echo "Webpack comparisons currently require the lockfile version (16.3.2)." >&2
        exit 2
      fi
      test -d node_modules
    else
      bun install --frozen-lockfile --minimum-release-age=0
      if [[ "$NEXT_VERSION" != "16.3.2" ]]; then
        bun add --exact --no-save --minimum-release-age=0 "next@${NEXT_VERSION}"
      fi
    fi
    (
      while true; do
        printf "%s," "$(date +%s)"
        cat /sys/fs/cgroup/memory.current
        sleep 1
      done
    ) > /results/memory.csv &
    sampler_pid=$!
    cleanup() {
      kill "$sampler_pid" 2>/dev/null || true
      wait "$sampler_pid" 2>/dev/null || true
      cat /sys/fs/cgroup/memory.events > /results/memory.events
    }
    trap cleanup EXIT
    {
      uname -a
      "$NEXT_RUNTIME" ./node_modules/next/dist/bin/next info
      "$NEXT_RUNTIME" scripts/generate.mjs
      build_args=()
      if [[ "$REPRO_BUNDLER" == "webpack" ]]; then
        build_args+=(--webpack)
      fi
      timeout --signal=TERM --kill-after=10s "${BUILD_TIMEOUT_SECONDS}s" \
        "$NEXT_RUNTIME" ./node_modules/next/dist/bin/next build "${build_args[@]}"
    } 2>&1 | tee /results/build.log
  '
status=$?
set -e

peak_bytes="$(awk -F, 'BEGIN { peak = 0 } $2 > peak { peak = $2 } END { print peak }' "${result_directory}/memory.csv")"
peak_mib="$((peak_bytes / 1024 / 1024))"
oom_kills="$(awk '$1 == "oom_kill" { print $2 }' "${result_directory}/memory.events")"
limit_events="$(awk '$1 == "max" { print $2 }' "${result_directory}/memory.events")"

printf 'Next.js: %s\nBundler: %s\nCPU limit: %s\nMemory limit: %s\nBuild timeout: %ss\nPeak cgroup memory: %s MiB\nAt-limit events: %s\nOOM kills: %s\nExit status: %s\n' \
  "${next_version}" "${bundler}" "${cpu_limit}" "${memory_limit}" "${build_timeout_seconds}" "${peak_mib}" "${limit_events:-0}" "${oom_kills:-0}" "${status}"

if [[ "${oom_kills:-0}" -gt 0 ]]; then
  exit 137
fi
exit "${status}"
