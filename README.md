# Next.js Turbopack build-memory reproduction

This repository generates a synthetic App Router project and runs `next build`
inside a Linux container with a hard memory limit. It contains no application
code or configuration from the project where the failure was first observed.

The default fixture approximates the observed project shape: 100 routes and
12,000 client modules compiled by Turbopack with the native React compiler. Each
module contains deterministic synthetic data so the fixture is generated from
a small, reviewable source file.

## Reproduce

Docker and Bun are required.

```bash
bun install --frozen-lockfile --minimum-release-age=0
bun run reproduce -- 16.3.2
```

The script constrains the container to 2 CPUs and 4 GB of memory, samples
cgroup memory once per second, and writes the build log, memory samples, and
cgroup counters to `results/<version>/`. A cgroup OOM exits with status 137.
Builds are bounded to 180 seconds and exit with status 124 so a process pinned
at the memory ceiling cannot thrash indefinitely.

Verify the current canary with:

```bash
bun run reproduce -- canary
```

## Observed native Linux x64 results

On the included GitHub Actions workflow with the default 2 CPU / 4 GB cgroup:

| Next.js | Bundler / configuration | Modules | Result | Cgroup evidence |
| --- | --- | ---: | --- | --- |
| 16.3.2 | Turbopack | 8,000 | Exit 0 in 65 seconds | 4,095 MiB peak; 5,331 at-limit events |
| 16.3.2 | Webpack memory optimizations | 8,000 | Exit 0 in 150 seconds | 4,095 MiB peak; 1,580 at-limit events |
| 16.3.2 | Turbopack | 12,000 | Exit 137 during compilation | 4,096 MiB peak; 206,580 at-limit events; one OOM kill |
| 16.4.0-canary.4 | Turbopack | 12,000 | Exit 124 during compilation | 4,096 MiB peak; 260,056 at-limit events |
| 16.3.2 | Turbopack, React Compiler disabled | 12,000 | Exit 124 during compilation | 4,096 MiB peak; 128,933 at-limit events |
| 16.3.2 | Turbopack, `experimental.cpus=1` | 12,000 | Exit 124 during compilation | 4,096 MiB peak; 252,981 at-limit events |
| 16.3.2 | Turbopack, plugin `workerThreads` | 12,000 | Exit 124 during compilation | 4,096 MiB peak; 251,080 at-limit events |
| 16.3.2 | Turbopack, `RAYON_NUM_THREADS=1` | 12,000 | Exit 124 during compilation | 4,096 MiB peak; 229,000 at-limit events |

Run the green control with:

```bash
REPRO_COMPONENTS_PER_ROUTE=80 bun run reproduce -- 16.3.2
```

The included GitHub Actions workflow runs the same reproduction on native
Linux x64 and uploads the build log, memory samples, and cgroup counters.

Fixture size and memory limit are configurable:

```bash
CPU_LIMIT=4 MEMORY_LIMIT=6g REPRO_ROUTES=80 REPRO_COMPONENTS_PER_ROUTE=48 \
  REPRO_ROWS_PER_COMPONENT=64 bun run reproduce -- canary
```

Set `NEXT_EXPERIMENTAL_CPUS=1` to isolate compilation from the default
page-data worker fan-out.

Set `REPRO_PLUGIN_RUNTIME_STRATEGY=workerThreads` to test Next.js's lower-memory
Turbopack backend for Node evaluation, or `RAYON_NUM_THREADS=1` to test whether
limiting Rayon changes the native compiler's memory profile.

Set `REPRO_REACT_COMPILER=false` to run the same graph without the React
Compiler transform.

To test Next.js's documented production-bundler fallback with its low-memory
Webpack mode enabled and the Turbopack-native React Compiler disabled:

```bash
REPRO_BUNDLER=webpack REPRO_COMPONENTS_PER_ROUTE=120 \
  bun run reproduce -- 16.3.2
```

## Expected behavior

`next build` should complete within the configured memory limit, or report an
actionable framework error instead of remaining in compilation while pinned at
the cgroup memory ceiling.

The measurements establish build-memory exhaustion and lack of forward
progress. They do not by themselves establish a time-based memory leak.
