/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  async rewrites() {
    // Use localhost for rewrites since frontend and backend run in the same container
    // const backendUrl = "http://localhost:12009";
    const backendUrl = "https://metamcp-backend-555166161772.us-central1.run.app"

    return [
      {
        source: "/health",
        destination: `${backendUrl}/health`,
      },
      {
        source: "/api/auth/:path*",
        destination: `${backendUrl}/api/auth/:path*`,
      },
      {
        source: "/trpc/:path*",
        destination: `${backendUrl}/trpc/frontend/:path*`,
      },
      {
        source: "/mcp-proxy/:path*",
        destination: `${backendUrl}/mcp-proxy/:path*`,
      },
      {
        source: "/metamcp/:path*",
        destination: `${backendUrl}/metamcp/:path*`,
      },
      {
        source: "/service/:path*",
        destination: "https://metatool-service.jczstudio.workers.dev/:path*",
      },
    ];
  },
};

export default nextConfig;
