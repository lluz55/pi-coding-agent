import type { OAuthCredentials, OAuthLoginCallbacks } from "@mariozechner/pi-ai";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import {
  loginQwen as loginQwenShared,
  refreshQwenToken as refreshQwenTokenShared,
} from "./oauth.mjs";

const QWEN_DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1";

function getQwenBaseUrl(resourceUrl?: string): string {
  if (!resourceUrl) {
    return QWEN_DEFAULT_BASE_URL;
  }

  let url = resourceUrl.startsWith("http") ? resourceUrl : `https://${resourceUrl}`;
  if (!url.endsWith("/v1")) {
    url = `${url}/v1`;
  }
  return url;
}

async function loginQwen(callbacks: OAuthLoginCallbacks): Promise<OAuthCredentials> {
  return loginQwenShared(callbacks);
}

async function refreshQwenToken(credentials: OAuthCredentials): Promise<OAuthCredentials> {
  return refreshQwenTokenShared(credentials);
}

export default function (pi: ExtensionAPI) {
  let lastSyncedEnterpriseUrl: string | null = null;

  const syncQwenModels = (ctx: any) => {
    const cred = ctx.modelRegistry.authStorage.get("qwen-cli");
    if (cred?.type !== "oauth") {
      lastSyncedEnterpriseUrl = null;
      return;
    }

    const enterpriseUrl = (cred as any).enterpriseUrl ?? "";
    if (enterpriseUrl === lastSyncedEnterpriseUrl) {
      return;
    }

    ctx.modelRegistry.refresh();
    lastSyncedEnterpriseUrl = enterpriseUrl;
  };

  pi.registerProvider("qwen-cli", {
    baseUrl: QWEN_DEFAULT_BASE_URL,
    apiKey: "QWEN_CLI_API_KEY",
    api: "openai-completions",
    models: [
      {
        id: "qwen3-coder-plus",
        name: "Qwen3 Coder Plus",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 1000000,
        maxTokens: 65536,
      },
      {
        id: "qwen3-coder-flash",
        name: "Qwen3 Coder Flash",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 1000000,
        maxTokens: 65536,
      },
      {
        id: "vision-model",
        name: "Qwen3 VL Plus",
        reasoning: true,
        input: ["text", "image"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 262144,
        maxTokens: 32768,
        compat: { supportsDeveloperRole: false, thinkingFormat: "qwen" },
      },
    ],
    oauth: {
      name: "Qwen CLI",
      login: loginQwen,
      refreshToken: refreshQwenToken,
      getApiKey: (cred) => cred.access,
      modifyModels: (models, cred) => {
        const baseUrl = getQwenBaseUrl(cred.enterpriseUrl as string | undefined);
        return models.map((m) => (m.provider === "qwen-cli" ? { ...m, baseUrl } : m));
      },
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    syncQwenModels(ctx);
  });

  pi.on("before_agent_start", async (_event, ctx) => {
    syncQwenModels(ctx);
  });
}
