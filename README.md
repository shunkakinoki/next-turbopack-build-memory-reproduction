# Next.js Turbopack build-memory reproduction

This repository generates a synthetic App Router project and runs `next build`
inside a Linux container with a hard memory limit. It contains no application
code or configuration from the project where the failure was first observed.

The default fixture approximates the observed project shape: 100 routes and
6,400 client modules compiled by Turbopack with the native React compiler. Each
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
cgroup OOM counts to `results/<version>/`. A cgroup OOM exits with status 137.
Builds are bounded to 180 seconds so a memory-thrashing process cannot run
indefinitely.

Verify the current canary with:

```bash
bun run reproduce -- canary
```

## Observed results

On Docker Desktop 29.7.2 with the default 2 CPU / 4 GB cgroup:

| Next.js | Modules | Result | Build stage |
| --- | ---: | --- | --- |
| 16.3.2 | 6,300 | Exit 0 | Completed |
| 16.3.2 | 6,400 | Exit 137, `oom_kill=1` (twice) | Collecting page data using 15 workers |
| 16.4.0-canary.4 | 6,400 | Exit 137, `oom_kill=1` | Collecting page data using 15 workers |

Run the green control with:

```bash
REPRO_COMPONENTS_PER_ROUTE=63 bun run reproduce -- 16.3.2
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

## Expected behavior

`next build` should complete within the configured memory limit, or report an
actionable framework error before the Linux cgroup kills a build process.
