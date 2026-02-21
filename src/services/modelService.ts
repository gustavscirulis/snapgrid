// Service for fetching, filtering, and selecting OpenAI vision-capable models

import { getApiKey } from "@/services/aiAnalysisService";

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

// Date-stamped snapshots like gpt-4o-2024-08-06 clutter the list —
// we only want the "latest" alias for each model family.
const DATE_SNAPSHOT_REGEX = /\d{4}-\d{2}-\d{2}/;

export const AUTO_MODEL_VALUE = "auto";
const PREFERENCE_KEY = "openai-model";
const FALLBACK_MODEL = "gpt-4o";

// In-memory cache (lasts for the session)
let cachedModels: OpenAIModel[] | null = null;

export function clearModelCache(): void {
  cachedModels = null;
}

export function isVisionCapable(modelId: string): boolean {
  const lower = modelId.toLowerCase();
  if (EXCLUDED_PATTERNS.some((pat) => lower.includes(pat))) return false;
  if (DATE_SNAPSHOT_REGEX.test(lower)) return false;
  return VISION_MODEL_PREFIXES.some((prefix) => lower.startsWith(prefix));
}

// Score models by generation and variant so "Use latest" picks the best
// general-purpose vision model, not just the newest API entry.
//
// Scoring: base score from model family + sub-version bonus - variant penalty
//   gpt-5.2      → 5200    gpt-5-mini  → 4990
//   gpt-5.1      → 5100    gpt-4.1     → 4100
//   gpt-5        → 5000    gpt-4o      → 4050
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

  // Penalize smaller variants
  if (lower.includes("-nano")) score -= 20;
  else if (lower.includes("-mini")) score -= 10;

  return score;
}

export async function fetchVisionModels(): Promise<OpenAIModel[]> {
  if (cachedModels) return cachedModels;

  let allModels: OpenAIModel[];

  if (window.electron?.listOpenAIModels) {
    const result = await window.electron.listOpenAIModels();
    if (!result.success || !result.models) {
      throw new Error(result.error || "Failed to fetch models");
    }
    allModels = result.models;
  } else {
    // Web fallback: direct fetch
    const apiKey = await getApiKey();
    if (!apiKey) throw new Error("API key not found");
    const response = await fetch("https://api.openai.com/v1/models", {
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!response.ok) throw new Error("Failed to fetch models");
    const data = await response.json();
    allModels = data.data;
  }

  cachedModels = allModels
    .filter((m) => isVisionCapable(m.id))
    .sort((a, b) => getModelScore(b.id) - getModelScore(a.id));

  return cachedModels;
}

export function getLatestModel(models: OpenAIModel[]): string {
  if (models.length === 0) return FALLBACK_MODEL;
  return models[0].id;
}

// Preference persistence via existing user preferences IPC
export async function getSelectedModel(): Promise<string> {
  if (window.electron?.getUserPreference) {
    const result = await window.electron.getUserPreference(
      PREFERENCE_KEY,
      AUTO_MODEL_VALUE
    );
    return result.success ? result.value || AUTO_MODEL_VALUE : AUTO_MODEL_VALUE;
  }
  return localStorage.getItem(PREFERENCE_KEY) || AUTO_MODEL_VALUE;
}

export async function setSelectedModel(modelId: string): Promise<void> {
  if (window.electron?.setUserPreference) {
    await window.electron.setUserPreference(PREFERENCE_KEY, modelId);
  } else {
    localStorage.setItem(PREFERENCE_KEY, modelId);
  }
}

// Resolve which model ID to actually use for analysis
export async function resolveModel(): Promise<string> {
  const preference = await getSelectedModel();

  if (preference === AUTO_MODEL_VALUE) {
    try {
      const models = await fetchVisionModels();
      return getLatestModel(models);
    } catch {
      return FALLBACK_MODEL;
    }
  }

  return preference;
}
