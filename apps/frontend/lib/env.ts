import { env } from "next-runtime-env";

export const getAppUrl = () => {
  const NEXT_PUBLIC_APP_URL = env("NEXT_PUBLIC_APP_URL");
  if (!NEXT_PUBLIC_APP_URL) {
    throw new Error("NEXT_PUBLIC_APP_URL is not set");
  }
  return NEXT_PUBLIC_APP_URL;
};

export const getApiUrl = () => {
  const NEXT_PUBLIC_API_URL = env("NEXT_PUBLIC_API_URL");
  if (!NEXT_PUBLIC_API_URL) {
    // NEVER fallback to frontend URL - always use backend
    // This is critical for auth to work properly
    console.warn('NEXT_PUBLIC_API_URL not available, using hardcoded backend URL');
    return 'https://metamcp-backend-555166161772.us-central1.run.app';
  }
  return NEXT_PUBLIC_API_URL;
};

// Helper function that ensures we always return an absolute URL for API calls
// This is specifically needed for middleware and server-side API calls
export const getAbsoluteApiUrl = () => {
  try {
    const apiUrl = getApiUrl();
    
    // If it's already an absolute URL, return as-is
    if (apiUrl.startsWith('http://') || apiUrl.startsWith('https://')) {
      return apiUrl;
    }
    
    // If it's a relative URL, we need to construct an absolute one
    // In server-side contexts (like middleware), we need to use the backend URL
    const NEXT_PUBLIC_API_URL = env("NEXT_PUBLIC_API_URL");
    if (NEXT_PUBLIC_API_URL && (NEXT_PUBLIC_API_URL.startsWith('http://') || NEXT_PUBLIC_API_URL.startsWith('https://'))) {
      return NEXT_PUBLIC_API_URL;
    }
    
    // Final fallback: construct absolute URL from APP_URL
    const appUrl = getAppUrl();
    if (appUrl.startsWith('http://') || appUrl.startsWith('https://')) {
      return appUrl;
    }
    
    // If we still don't have an absolute URL, throw an error
    throw new Error(`Cannot construct absolute API URL. NEXT_PUBLIC_API_URL: ${NEXT_PUBLIC_API_URL}, APP_URL: ${appUrl}`);
  } catch (error) {
    // Fallback to hardcoded backend URL if environment resolution fails
    // This is specifically for middleware contexts where next-runtime-env might not work
    console.warn('Failed to get API URL from environment, using fallback:', error);
    return 'https://metamcp-backend-555166161772.us-central1.run.app';
  }
};
