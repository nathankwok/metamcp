import { genericOAuthClient } from "better-auth/client/plugins";
import { createAuthClient } from "better-auth/react";

import { getApiUrl } from "./env";

export const authClient = createAuthClient({
  baseURL: getApiUrl(),
  plugins: [genericOAuthClient()],
}) as ReturnType<typeof createAuthClient>;
