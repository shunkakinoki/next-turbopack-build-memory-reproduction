import type { NextConfig } from "next";

const experimentalCpus = process.env.NEXT_EXPERIMENTAL_CPUS
  ? Number.parseInt(process.env.NEXT_EXPERIMENTAL_CPUS, 10)
  : undefined;

const nextConfig: NextConfig = {
  reactCompiler: true,
  experimental: {
    ...(experimentalCpus ? { cpus: experimentalCpus } : {}),
    turbopackRustReactCompiler: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
};

export default nextConfig;
