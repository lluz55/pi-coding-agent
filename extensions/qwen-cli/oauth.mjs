import { promises as fs } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const QWEN_DEVICE_CODE_ENDPOINT = "https://chat.qwen.ai/api/v1/oauth2/device/code";
const QWEN_TOKEN_ENDPOINT = "https://chat.qwen.ai/api/v1/oauth2/token";
const QWEN_CLIENT_ID = "f0304373b74a44d2b584a3fb70ca9e56";
const QWEN_SCOPE = "openid profile email model.completion";
const QWEN_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code";
const QWEN_DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1";
const QWEN_POLL_INTERVAL_MS = 2000;
const QWEN_REFRESH_BUFFER_MS = 5 * 60 * 1000;

function isObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function now() {
  return Date.now();
}

function normalizeBaseUrl(resourceUrl) {
  if (!resourceUrl) {
    return QWEN_DEFAULT_BASE_URL;
  }

  let url = resourceUrl.startsWith("http") ? resourceUrl : `https://${resourceUrl}`;
  if (!url.endsWith("/v1")) {
    url = `${url}/v1`;
  }
  return url;
}

function normalizeAuthRecord(raw) {
  if (!isObject(raw)) {
    return null;
  }

  const candidate = raw["qwen-cli"] ?? raw.qwen ?? raw;
  if (!isObject(candidate)) {
    return null;
  }

  const access = candidate.access ?? candidate.access_token;
  const refresh = candidate.refresh ?? candidate.refresh_token ?? "";
  const expires = candidate.expires ?? candidate.expiry_date;
  const enterpriseUrl = candidate.enterpriseUrl ?? candidate.resourceUrl ?? candidate.resource_url ?? "";
  const type = candidate.type ?? "oauth";

  if (type !== "oauth" || typeof access !== "string" || !access || typeof expires !== "number") {
    return null;
  }

  return {
    type: "oauth",
    access,
    refresh: typeof refresh === "string" ? refresh : "",
    expires,
    enterpriseUrl: typeof enterpriseUrl === "string" ? enterpriseUrl : "",
  };
}

function toAuthStoragePayload(credentials) {
  const record = normalizeAuthRecord(credentials);
  if (!record) {
    throw new Error("Invalid Qwen credentials");
  }

  return {
    "qwen-cli": {
      type: "oauth",
      access: record.access,
      access_token: record.access,
      refresh: record.refresh,
      refresh_token: record.refresh,
      expires: record.expires,
      expiry_date: record.expires,
      enterpriseUrl: record.enterpriseUrl,
      resourceUrl: record.enterpriseUrl,
      resource_url: record.enterpriseUrl,
    },
  };
}

async function readJsonFile(filePath) {
  try {
    const text = await fs.readFile(filePath, "utf8");
    return JSON.parse(text);
  } catch {
    return null;
  }
}

async function writeJsonAtomic(filePath, payload) {
  await fs.mkdir(dirname(filePath), { recursive: true });
  const tmpFile = join(dirname(filePath), `.${process.pid}.${Math.random().toString(16).slice(2)}.tmp`);
  await fs.writeFile(tmpFile, `${JSON.stringify(payload, null, 2)}\n`, { mode: 0o600 });
  await fs.rename(tmpFile, filePath);
  await fs.chmod(filePath, 0o600);
}

async function removeFile(filePath) {
  try {
    await fs.unlink(filePath);
  } catch (error) {
    if (error?.code !== "ENOENT") {
      throw error;
    }
  }
}

function abortableSleep(ms, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new Error("Login cancelled"));
      return;
    }

    const timeout = setTimeout(resolve, ms);
    signal?.addEventListener(
      "abort",
      () => {
        clearTimeout(timeout);
        reject(new Error("Login cancelled"));
      },
      { once: true },
    );
  });
}

async function openBrowser(url) {
  const commands = [
    ["xdg-open", [url]],
    ["open", [url]],
    ["cmd", ["/c", "start", "", url]],
  ];

  for (const [command, args] of commands) {
    const result = spawnSync(command, args, { stdio: "ignore" });
    if (!result.error && result.status === 0) {
      return true;
    }
  }

  return false;
}

async function startDeviceFlow() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  const verifier = btoa(String.fromCharCode(...array))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const challenge = btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const body = new URLSearchParams({
    client_id: QWEN_CLIENT_ID,
    scope: QWEN_SCOPE,
    code_challenge: challenge,
    code_challenge_method: "S256",
  });

  const response = await fetch(QWEN_DEVICE_CODE_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Device code request failed: ${response.status} ${text}`);
  }

  const deviceCode = await response.json();
  if (!deviceCode.device_code || !deviceCode.user_code || !deviceCode.verification_uri) {
    throw new Error("Invalid device code response: missing required fields");
  }

  return { deviceCode, verifier };
}

async function pollForToken(deviceCode, verifier, intervalSeconds, expiresIn, signal) {
  const deadline = now() + expiresIn * 1000;
  const resolvedIntervalSeconds =
    typeof intervalSeconds === "number" && Number.isFinite(intervalSeconds) && intervalSeconds > 0
      ? intervalSeconds
      : QWEN_POLL_INTERVAL_MS / 1000;
  let intervalMs = Math.max(1000, Math.floor(resolvedIntervalSeconds * 1000));

  const handleTokenError = async (error, description) => {
    switch (error) {
      case "authorization_pending":
        await abortableSleep(intervalMs, signal);
        return true;
      case "slow_down":
        intervalMs = Math.min(intervalMs + 5000, 10000);
        await abortableSleep(intervalMs, signal);
        return true;
      case "expired_token":
        throw new Error("Device code expired. Please restart authentication.");
      case "access_denied":
        throw new Error("Authorization denied by user.");
      default:
        throw new Error(`Token request failed: ${error} - ${description || ""}`);
    }
  };

  while (now() < deadline) {
    if (signal?.aborted) {
      throw new Error("Login cancelled");
    }

    const body = new URLSearchParams({
      grant_type: QWEN_GRANT_TYPE,
      client_id: QWEN_CLIENT_ID,
      device_code: deviceCode,
      code_verifier: verifier,
    });

    const response = await fetch(QWEN_TOKEN_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: body.toString(),
    });

    const responseText = await response.text();
    let data = null;
    if (responseText) {
      try {
        data = JSON.parse(responseText);
      } catch {
        data = null;
      }
    }

    const error = data?.error;
    const errorDescription = data?.error_description;

    if (!response.ok) {
      if (error && (await handleTokenError(error, errorDescription))) {
        continue;
      }
      throw new Error(`Token request failed: ${response.status} ${response.statusText}. Response: ${responseText}`);
    }

    if (data?.access_token) {
      return data;
    }

    if (error && (await handleTokenError(error, errorDescription))) {
      continue;
    }

    throw new Error("Token request failed: missing access token in response");
  }

  throw new Error("Authentication timed out. Please try again.");
}

function createAuthRecord(tokenResponse) {
  return {
    type: "oauth",
    access: tokenResponse.access_token,
    access_token: tokenResponse.access_token,
    refresh: tokenResponse.refresh_token || "",
    refresh_token: tokenResponse.refresh_token || "",
    expires: now() + tokenResponse.expires_in * 1000 - QWEN_REFRESH_BUFFER_MS,
    expiry_date: now() + tokenResponse.expires_in * 1000 - QWEN_REFRESH_BUFFER_MS,
    enterpriseUrl: tokenResponse.resource_url || "",
    resourceUrl: tokenResponse.resource_url || "",
    resource_url: tokenResponse.resource_url || "",
  };
}

export function isValidQwenAuthRecord(record) {
  return Boolean(
    record &&
      record.type === "oauth" &&
      typeof record.access === "string" &&
      record.access.length > 0 &&
      typeof record.expires === "number" &&
      record.expires > now() + QWEN_REFRESH_BUFFER_MS,
  );
}

export async function readQwenAuthFile(authFilePath) {
  return normalizeAuthRecord(await readJsonFile(authFilePath));
}

export async function writeQwenAuthFile(authFilePath, credentials) {
  await writeJsonAtomic(authFilePath, toAuthStoragePayload(credentials));
}

export async function clearQwenAuthFile(authFilePath) {
  await removeFile(authFilePath);
}

export async function loginQwen(options = {}) {
  const { signal, onAuth } = options;
  const { deviceCode, verifier } = await startDeviceFlow();
  const authUrl = deviceCode.verification_uri_complete || deviceCode.verification_uri;
  const instructions = deviceCode.verification_uri_complete ? undefined : `Enter code: ${deviceCode.user_code}`;

  if (typeof onAuth === "function") {
    onAuth({ url: authUrl, instructions });
  } else {
    console.log(`Open: ${authUrl}`);
    if (instructions) {
      console.log(instructions);
    }
    if (!(await openBrowser(authUrl))) {
      console.log("Browser launch failed; open the URL manually.");
    }
  }

  const tokenResponse = await pollForToken(
    deviceCode.device_code,
    verifier,
    deviceCode.interval,
    deviceCode.expires_in,
    signal,
  );

  return createAuthRecord(tokenResponse);
}

export async function refreshQwenToken(credentials) {
  const refreshToken = credentials.refresh ?? credentials.refresh_token;
  if (!refreshToken) {
    throw new Error("Token refresh failed: no refresh token in credentials");
  }

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: QWEN_CLIENT_ID,
  });

  const response = await fetch(QWEN_TOKEN_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Token refresh failed: ${response.status} ${text}`);
  }

  const data = await response.json();
  if (!data.access_token) {
    throw new Error("Token refresh failed: no access token in response");
  }

  return {
    type: "oauth",
    access: data.access_token,
    access_token: data.access_token,
    refresh: data.refresh_token || refreshToken,
    refresh_token: data.refresh_token || refreshToken,
    expires: now() + data.expires_in * 1000 - QWEN_REFRESH_BUFFER_MS,
    expiry_date: now() + data.expires_in * 1000 - QWEN_REFRESH_BUFFER_MS,
    enterpriseUrl: data.resource_url ?? credentials.enterpriseUrl ?? credentials.resourceUrl ?? "",
    resourceUrl: data.resource_url ?? credentials.enterpriseUrl ?? credentials.resourceUrl ?? "",
    resource_url: data.resource_url ?? credentials.enterpriseUrl ?? credentials.resourceUrl ?? "",
  };
}

export async function ensureQwenAuthFile(authFilePath, options = {}) {
  const { logout = false, reauth = false, signal } = options;

  if (logout) {
    await clearQwenAuthFile(authFilePath);
  }

  const existing = await readQwenAuthFile(authFilePath);
  if (existing && !reauth) {
    if (isValidQwenAuthRecord(existing)) {
      return existing;
    }

    if (existing.refresh) {
      try {
        const refreshed = await refreshQwenToken(existing);
        await writeQwenAuthFile(authFilePath, refreshed);
        return refreshed;
      } catch {
        // Fall through to interactive login.
      }
    }
  }

  const fresh = await loginQwen({ signal });
  await writeQwenAuthFile(authFilePath, fresh);
  return fresh;
}

async function main(argv) {
  const options = {
    authFile: null,
    logout: false,
    reauth: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--auth-file") {
      options.authFile = argv[++i];
      continue;
    }
    if (arg === "--logout") {
      options.logout = true;
      continue;
    }
    if (arg === "--reauth" || arg === "--login") {
      options.reauth = true;
      continue;
    }
  }

  if (!options.authFile) {
    throw new Error("Missing --auth-file");
  }

  const record = await ensureQwenAuthFile(options.authFile, {
    logout: options.logout,
    reauth: options.reauth,
  });

  console.log(`Qwen OAuth ready for ${normalizeBaseUrl(record.enterpriseUrl)}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
