import { genericOAuthClient } from "better-auth/client/plugins";
import { createAuthClient } from "better-auth/react";

import { getAppUrl } from "./env";

export const authClient = createAuthClient({
  // Use frontend URL so auth requests go to our proxy routes
  // The proxy routes will forward them to the backend
  baseURL: getAppUrl(),
  plugins: [genericOAuthClient()],
}) as ReturnType<typeof createAuthClient>;
