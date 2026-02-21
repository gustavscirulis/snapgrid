// Service for fetching, filtering, and selecting vision-capable models
// Supports both OpenAI and Anthropic Claude providers

import { getApiKey } from "@/services/aiAnalysisService";

// ── Provider type ──────────────────────────────────────────────────

export type AIProvider = "openai" | "anthropic" | "gemini";

const PROVIDER_PREFERENCE_KEY = "ai-provider";

export async function getActiveProvider(): Promise<AIProvider> {
  if (window.electron?.getUserPreference) {
    const result = await window.electron.getUserPreference(PROVIDER_PREFERENCE_KEY, "openai");
    return (result.success ? result.value : "openai") as AIProvider;
  }
  return (localStorage.getItem(PROVIDER_PREFERENCE_KEY) as AIProvider) || "openai";
}

export async function setActiveProvider(provider: AIProvider): Promise<void> {
  if (window.electron?.setUserPreference) {
    await window.electron.setUserPreference(PROVIDER_PREFERENCE_KEY, provider);
  } else {
    localStorage.setItem(PROVIDER_PREFERENCE_KEY, provider);
  }
}

// ── Shared constants ───────────────────────────────────────────────

export const AUTO_MODEL_VALUE = "auto";

// Date-stamped snapshots like gpt-4o-2024-08-06 or claude-sonnet-4-5-20250514
// clutter the list — we only want the "latest" alias for each model family.
const DATE_SNAPSHOT_REGEX = /\d{4}-?\d{2}-?\d{2}/;

// ── OpenAI ─────────────────────────────────────────────────────────

export interface OpenAIModel {
  id: string;
  created: number;
  owned_by: string;
}

// GPT model families suitable for image analysis via Chat Completions API.
// Excludes reasoning models (o1/o3/o4) which are slow, expensive, and
// overkill for image classification, and gpt-4-turbo which is superseded.
const VISION_MODEL_PREFIXES = [
  "gpt-4o",
  "gpt-4.1",
  "gpt-5",
];

// Substrings that indicate non-vision or specialized models (always excluded)
const EXCLUDED_PATTERNS = [
  "embedding",
  "tts",
  "whisper",
  "dall-e",
  "davinci",
  "babbage",
  "moderation",
  "realtime",
  "transcribe",
  "audio",
  "search",
  "codex",
  "codecs",
  "image",    // gpt-5-image-* are generation models, not analysis
  "preview",  // preview models are unstable
];

const OPENAI_PREFERENCE_KEY = "openai-model";
const OPENAI_FALLBACK_MODEL = "gpt-4o";

let cachedOpenAIModels: OpenAIModel[] | null = null;

export function clearModelCache(): void {
  cachedOpenAIModels = null;
  cachedClaudeModels = null;
  cachedGeminiModels = null;
}

export function isVisionCapable(modelId: string): boolean {
  const lower = modelId.toLowerCase();
  if (EXCLUDED_PATTERNS.some((pat) => lower.includes(pat))) return false;
  if (DATE_SNAPSHOT_REGEX.test(lower)) return false;
  return VISION_MODEL_PREFIXES.some((prefix) => lower.startsWith(prefix));
}

// Score models by generation and variant so "Use latest" picks the best
// general-purpose vision model, not just the newest API entry.
function getModelScore(modelId: string): number {
  const lower = modelId.toLowerCase();
  let score = 0;

  if (lower.startsWith("gpt-5")) {
    score = 5000;
    const subVersion = lower.match(/^gpt-5\.(\d+)/);
    if (subVersion) score += parseInt(subVersion[1]) * 100;
  } else if (lower.startsWith("gpt-4.1")) {
    score = 4100;
  } else if (lower.startsWith("gpt-4o")) {
    score = 4050;
  }

  if (lower.includes("-nano")) score -= 20;
  else if (lower.includes("-mini")) score -= 10;

  return score;
}

export async function fetchVisionModels(): Promise<OpenAIModel[]> {
  if (cachedOpenAIModels) return cachedOpenAIModels;

  let allModels: OpenAIModel[];

  if (window.electron?.listOpenAIModels) {
    const result = await window.electron.listOpenAIModels();
    if (!result.success || !result.models) {
      throw new Error(result.error || "Failed to fetch models");
    }
    allModels = result.models;
  } else {
    const apiKey = await getApiKey();
    if (!apiKey) throw new Error("API key not found");
    const response = await fetch("https://api.openai.com/v1/models", {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!response.ok) throw new Error("Failed to fetch models");
    const data = await response.json();
    allModels = data.data;
  }

  cachedOpenAIModels = allModels
    .filter((m) => isVisionCapable(m.id))
    .sort((a, b) => getModelScore(b.id) - getModelScore(a.id));

  return cachedOpenAIModels;
}

export function getLatestModel(models: Array<{ id: string }>): string {
  if (models.length === 0) return OPENAI_FALLBACK_MODEL;
  return models[0].id;
}

export async function getSelectedModel(): Promise<string> {
  if (window.electron?.getUserPreference) {
    const result = await window.electron.getUserPreference(
      OPENAI_PREFERENCE_KEY,
      AUTO_MODEL_VALUE
    );
    return result.success ? result.value || AUTO_MODEL_VALUE : AUTO_MODEL_VALUE;
  }
  return localStorage.getItem(OPENAI_PREFERENCE_KEY) || AUTO_MODEL_VALUE;
}

export async function setSelectedModel(modelId: string): Promise<void> {
  if (window.electron?.setUserPreference) {
    await window.electron.setUserPreference(OPENAI_PREFERENCE_KEY, modelId);
  } else {
    localStorage.setItem(OPENAI_PREFERENCE_KEY, modelId);
  }
}

// ── Anthropic Claude ───────────────────────────────────────────────

export interface ClaudeModel {
  id: string;
  display_name: string;
  created_at: string;
}

const CLAUDE_PREFERENCE_KEY = "anthropic-model";
const CLAUDE_FALLBACK_MODEL = "claude-sonnet-4-5";

let cachedClaudeModels: ClaudeModel[] | null = null;

// Only include Claude model families that support vision (image input).
// Exclude date-stamped snapshots to keep the list clean.
export function isClaudeVisionCapable(modelId: string): boolean {
  const lower = modelId.toLowerCase();
  if (!lower.startsWith("claude-")) return false;
  if (DATE_SNAPSHOT_REGEX.test(lower)) return false;
  return true;
}

// Score Claude models so "Use latest" picks the best value for image analysis.
// Sonnet is the sweet spot (fast, capable, affordable). Opus is overkill for
// classification tasks. Haiku is cheapest but less capable.
//   sonnet > opus > haiku
//   higher version numbers score higher (4.5 > 4.0 > 3.5)
function getClaudeModelScore(modelId: string): number {
  const lower = modelId.toLowerCase();
  let score = 0;

  // Version score: extract the version number (e.g. "4-5" → 4.5)
  const versionMatch = lower.match(/claude-\w+-(\d+)-(\d+)/);
  if (versionMatch) {
    score += parseFloat(`${versionMatch[1]}.${versionMatch[2]}`) * 1000;
  }

  // Tier score: sonnet preferred for best cost/quality tradeoff
  if (lower.includes("sonnet")) score += 300;
  else if (lower.includes("opus")) score += 200;
  else if (lower.includes("haiku")) score += 100;

  return score;
}

export async function fetchClaudeModels(): Promise<ClaudeModel[]> {
  if (cachedClaudeModels) return cachedClaudeModels;

  let allModels: ClaudeModel[];

  if (window.electron?.listClaudeModels) {
    const result = await window.electron.listClaudeModels();
    if (!result.success || !result.models) {
      throw new Error(result.error || "Failed to fetch Claude models");
    }
    allModels = result.models;
  } else {
    // Web fallback: direct fetch (will likely hit CORS, but matches OpenAI pattern)
    const response = await fetch("https://api.anthropic.com/v1/models?limit=1000", {
      headers: {
        "x-api-key": "", // Would need key from localStorage — unlikely path
        "anthropic-version": "2023-06-01",
      },
    });
    if (!response.ok) throw new Error("Failed to fetch Claude models");
    const data = await response.json();
    allModels = data.data;
  }

  cachedClaudeModels = allModels
    .filter((m) => isClaudeVisionCapable(m.id))
    .sort((a, b) => getClaudeModelScore(b.id) - getClaudeModelScore(a.id));

  return cachedClaudeModels;
}

export function getLatestClaudeModel(models: ClaudeModel[]): string {
  if (models.length === 0) return CLAUDE_FALLBACK_MODEL;
  return models[0].id;
}

export async function getSelectedClaudeModel(): Promise<string> {
  if (window.electron?.getUserPreference) {
    const result = await window.electron.getUserPreference(
      CLAUDE_PREFERENCE_KEY,
      AUTO_MODEL_VALUE
    );
    return result.success ? result.value || AUTO_MODEL_VALUE : AUTO_MODEL_VALUE;
  }
  return localStorage.getItem(CLAUDE_PREFERENCE_KEY) || AUTO_MODEL_VALUE;
}

export async function setSelectedClaudeModel(modelId: string): Promise<void> {
  if (window.electron?.setUserPreference) {
    await window.electron.setUserPreference(CLAUDE_PREFERENCE_KEY, modelId);
  } else {
    localStorage.setItem(CLAUDE_PREFERENCE_KEY, modelId);
  }
}

// ── Google Gemini ─────────────────────────────────────────────────

export interface GeminiModel {
  id: string;
  display_name: string;
}

const GEMINI_PREFERENCE_KEY = "gemini-model";
const GEMINI_FALLBACK_MODEL = "gemini-2.0-flash";

let cachedGeminiModels: GeminiModel[] | null = null;

export function isGeminiVisionCapable(modelId: string): boolean {
  const lower = modelId.toLowerCase();
  if (!lower.includes("gemini")) return false;
  if (DATE_SNAPSHOT_REGEX.test(lower)) return false;
  const excluded = ["embedding", "aqa", "text", "tuning"];
  if (excluded.some((pat) => lower.includes(pat))) return false;
  return true;
}

function getGeminiModelScore(modelId: string): number {
  const lower = modelId.toLowerCase();
  let score = 0;

  const versionMatch = lower.match(/gemini-(\d+)\.(\d+)/);
  if (versionMatch) {
    score += (parseInt(versionMatch[1]) * 10 + parseInt(versionMatch[2])) * 100;
  }

  if (lower.includes("pro")) score += 50;
  else if (lower.includes("flash")) score += 30;

  return score;
}

export async function fetchGeminiModels(): Promise<GeminiModel[]> {
  if (cachedGeminiModels) return cachedGeminiModels;

  let allModels: GeminiModel[];

  if (window.electron?.listGeminiModels) {
    const result = await window.electron.listGeminiModels();
    if (!result.success || !result.models) {
      throw new Error(result.error || "Failed to fetch Gemini models");
    }
    allModels = result.models;
  } else {
    const response = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models?key="
    );
    if (!response.ok) throw new Error("Failed to fetch Gemini models");
    const data = await response.json();
    allModels = data.models.map((m: { name: string; displayName: string }) => ({
      id: m.name.replace("models/", ""),
      display_name: m.displayName,
    }));
  }

  cachedGeminiModels = allModels
    .filter((m) => isGeminiVisionCapable(m.id))
    .sort((a, b) => getGeminiModelScore(b.id) - getGeminiModelScore(a.id));

  return cachedGeminiModels;
}

export function getLatestGeminiModel(models: GeminiModel[]): string {
  if (models.length === 0) return GEMINI_FALLBACK_MODEL;
  return models[0].id;
}

export async function getSelectedGeminiModel(): Promise<string> {
  if (window.electron?.getUserPreference) {
    const result = await window.electron.getUserPreference(
      GEMINI_PREFERENCE_KEY,
      AUTO_MODEL_VALUE
    );
    return result.success ? result.value || AUTO_MODEL_VALUE : AUTO_MODEL_VALUE;
  }
  return localStorage.getItem(GEMINI_PREFERENCE_KEY) || AUTO_MODEL_VALUE;
}

export async function setSelectedGeminiModel(modelId: string): Promise<void> {
  if (window.electron?.setUserPreference) {
    await window.electron.setUserPreference(GEMINI_PREFERENCE_KEY, modelId);
  } else {
    localStorage.setItem(GEMINI_PREFERENCE_KEY, modelId);
  }
}

// ── Unified resolution ─────────────────────────────────────────────

// Resolve which model ID to actually use for analysis, based on active provider
export async function resolveModel(): Promise<string> {
  const provider = await getActiveProvider();

  if (provider === "anthropic") {
    const preference = await getSelectedClaudeModel();
    if (preference === AUTO_MODEL_VALUE) {
      try {
        const models = await fetchClaudeModels();
        return getLatestClaudeModel(models);
      } catch {
        return CLAUDE_FALLBACK_MODEL;
      }
    }
    return preference;
  }

  if (provider === "gemini") {
    const preference = await getSelectedGeminiModel();
    if (preference === AUTO_MODEL_VALUE) {
      try {
        const models = await fetchGeminiModels();
        return getLatestGeminiModel(models);
      } catch {
        return GEMINI_FALLBACK_MODEL;
      }
    }
    return preference;
  }

  // OpenAI path (default)
  const preference = await getSelectedModel();
  if (preference === AUTO_MODEL_VALUE) {
    try {
      const models = await fetchVisionModels();
      return getLatestModel(models);
    } catch {
      return OPENAI_FALLBACK_MODEL;
    }
  }
  return preference;
}
