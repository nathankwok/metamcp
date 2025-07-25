/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
  // Removed proxy rewrites since frontend and backend are now deployed separately
  // and API calls use absolute URLs to the backend service
};

export default nextConfig;
