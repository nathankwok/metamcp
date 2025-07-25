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
    // Fallback to APP_URL for backwards compatibility
    return getAppUrl();
  }
  return NEXT_PUBLIC_API_URL;
};
