/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The shared package is TypeScript source in the workspace, so Next has to
  // compile it rather than expect a prebuilt bundle.
  transpilePackages: ['@tsp/shared'],
  env: {
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL ?? 'http://localhost:3000/api',
  },
};

export default nextConfig;
