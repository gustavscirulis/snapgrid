// A service to identify UI patterns in images using AI vision APIs (OpenAI and Anthropic Claude)
import { sendAnalyticsEvent } from "@/services/analyticsService";
import { resolveModel, getActiveProvider, type AIProvider } from "@/services/modelService";

interface PatternMatch {
  name: string;
  confidence: number;
  imageContext: string;
  imageSummary: string;
}

interface AnalysisResponse {
  imageContext: string;
  imageSummary: string;
  patterns: Omit<PatternMatch, 'imageContext' | 'imageSummary'>[];
}

// ── API key handling ───────────────────────────────────────────────

async function setApiKeyForService(service: string, key: string): Promise<boolean> {
  try {
    if (window.electron && window.electron.setApiKey) {
      const result = await window.electron.setApiKey(service, key);
      if (result.success) {
        sendAnalyticsEvent('api-key-added', { service });
      }
      return result.success;
    } else {
      localStorage.setItem(`${service}-api-key`, key);
      sendAnalyticsEvent('api-key-added', { service });
      return true;
    }
  } catch (error) {
    console.error(`Error storing ${service} API key:`, error);
    return false;
  }
}

async function hasApiKeyForService(service: string): Promise<boolean> {
  try {
    if (window.electron && window.electron.hasApiKey) {
      const result = await window.electron.hasApiKey(service);
      return result.success && result.hasKey;
    } else {
      return !!localStorage.getItem(`${service}-api-key`);
    }
  } catch (error) {
    console.error(`Error checking ${service} API key:`, error);
    return false;
  }
}

async function getApiKeyForService(service: string): Promise<string | null> {
  try {
    if (window.electron && window.electron.getApiKey) {
      const result = await window.electron.getApiKey(service);
      return result.success ? result.key : null;
    } else {
      return localStorage.getItem(`${service}-api-key`);
    }
  } catch (error) {
    console.error(`Error retrieving ${service} API key:`, error);
    return null;
  }
}

async function deleteApiKeyForService(service: string): Promise<boolean> {
  try {
    if (window.electron && window.electron.deleteApiKey) {
      const result = await window.electron.deleteApiKey(service);
      if (result.success) {
        sendAnalyticsEvent('api-key-removed', { service });
      }
      return result.success;
    } else {
      localStorage.removeItem(`${service}-api-key`);
      sendAnalyticsEvent('api-key-removed', { service });
      return true;
    }
  } catch (error) {
    console.error(`Error deleting ${service} API key:`, error);
    return false;
  }
}

// Public API key functions — delegate to the appropriate service

export async function setOpenAIApiKey(key: string): Promise<boolean> {
  return setApiKeyForService('openai', key);
}

export async function setAnthropicApiKey(key: string): Promise<boolean> {
  return setApiKeyForService('anthropic', key);
}

export async function hasApiKey(provider?: AIProvider): Promise<boolean> {
  const p = provider ?? await getActiveProvider();
  return hasApiKeyForService(p === 'anthropic' ? 'anthropic' : 'openai');
}

export async function getApiKey(): Promise<string | null> {
  return getApiKeyForService('openai');
}

export async function getAnthropicApiKey(): Promise<string | null> {
  return getApiKeyForService('anthropic');
}

export async function deleteApiKey(provider?: AIProvider): Promise<boolean> {
  const p = provider ?? await getActiveProvider();
  return deleteApiKeyForService(p === 'anthropic' ? 'anthropic' : 'openai');
}

// ── Shared prompt ──────────────────────────────────────────────────

export const DEFAULT_SYSTEM_PROMPT = `You are an expert AI in analyzing images. Your task is to analyze the content of images and provide appropriate descriptions.

    Provide your response in the following JSON format:
    {
      "imageContext": "Detailed description of the entire image, including its purpose and main characteristics",
      "imageSummary": "Very brief summary (1-2 words) of the main content or purpose",
      "patterns": [
        {
          "name": "Main object, subject, or element",
          "confidence": 0.95
        }
      ]
    }

    Guidelines:
      1. The "imageSummary" should be a very brief (1-2 words) description of what the image shows
      2. The "imageContext" should provide detailed information about the entire image
      3. List the most prominent objects, subjects, or elements visible in the image
      4. Use specific, descriptive language appropriate to the content (e.g. technical terms for UI screenshots, descriptive language for photos)
      5. Each pattern should be 1-2 words maximum, not duplicative of imageSummary
      6. Include confidence scores between 0.8 and 1.0
      7. List patterns in order of confidence/importance
      8. Ensure that the patterns are unique and not duplicates of each other and imageSummary
      9. Provide exactly 6 patterns, ordered by confidence`;

const USER_TEXT = "Analyze this image and provide a detailed breakdown of its content. If it's a UI screenshot, focus on UI patterns and components. If it's a general scene, focus on objects and subjects. Respond with a strict, valid JSON object in the format specified in the system prompt. Do not include markdown formatting, explanations, or code block symbols. Use title case for pattern/object names. Provide up to 6 patterns/objects, ordered by confidence.";

// ── Response parsing (shared by both providers) ────────────────────

function parseAnalysisResponse(content: string): PatternMatch[] {
  try {
    let jsonString = content;

    // Clean up common markdown formatting
    if (content.includes('```json')) {
      jsonString = content.split('```json')[1].split('```')[0].trim();
    } else if (content.includes('```')) {
      jsonString = content.split('```')[1].split('```')[0].trim();
    }

    const response = JSON.parse(jsonString) as AnalysisResponse;

    if (response.patterns && Array.isArray(response.patterns)) {
      return response.patterns
        .filter(p => p && p.name && typeof p.confidence === 'number' && p.confidence >= 0.7)
        .map(p => ({
          name: p.name,
          confidence: Math.min(Math.max(p.confidence, 0), 1),
          imageContext: response.imageContext,
          imageSummary: response.imageSummary
        }))
        .sort((a, b) => b.confidence - a.confidence)
        .slice(0, 6);
    }
    throw new Error('Invalid response format');
  } catch {
    // Try aggressive cleanup
    let jsonString = content.replace(/```/g, '').replace(/json/g, '').trim();

    const objectMatch = jsonString.match(/\{[\s\S]*\}/);
    if (objectMatch) {
      jsonString = objectMatch[0];
    }

    const response = JSON.parse(jsonString) as AnalysisResponse;

    if (response.patterns && Array.isArray(response.patterns)) {
      return response.patterns
        .filter(p => p && p.name && typeof p.confidence === 'number' && p.confidence >= 0.7)
        .map(p => ({
          name: p.name,
          confidence: Math.min(Math.max(p.confidence, 0), 1),
          imageContext: response.imageContext,
          imageSummary: response.imageSummary
        }))
        .sort((a, b) => b.confidence - a.confidence)
        .slice(0, 6);
    }
    throw new Error('Invalid response format');
  }
}

// ── Base64 extraction for Claude ───────────────────────────────────

function extractBase64(dataUrl: string): { data: string; mediaType: string } {
  const [header, data] = dataUrl.split(',');
  const mediaType = header.replace('data:', '').replace(';base64', '');
  return { data, mediaType };
}

// ── OpenAI analysis ────────────────────────────────────────────────

async function analyzeImageWithOpenAI(imageUrl: string, modelId: string, systemPrompt: string): Promise<PatternMatch[]> {
  const payload = {
    model: modelId,
    messages: [
      {
        role: "system",
        content: systemPrompt
      },
      {
        role: "user",
        content: [
          { type: "text", text: USER_TEXT },
          { type: "image_url", image_url: { url: imageUrl } }
        ]
      }
    ],
    max_completion_tokens: 800
  };

  let data;

  if (window.electron && window.electron.callOpenAI) {
    data = await window.electron.callOpenAI(payload);
  } else {
    const apiKey = await getApiKey();
    if (!apiKey) throw new Error("API key not found");

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
    }

    data = await response.json();
  }

  const content = data.choices[0]?.message?.content;
  return parseAnalysisResponse(content);
}

// ── Claude analysis ────────────────────────────────────────────────

async function analyzeImageWithClaude(imageUrl: string, modelId: string, systemPrompt: string): Promise<PatternMatch[]> {
  const { data: base64Data, mediaType } = extractBase64(imageUrl);

  const payload = {
    model: modelId,
    max_tokens: 800,
    system: systemPrompt,
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image",
            source: {
              type: "base64",
              media_type: mediaType,
              data: base64Data
            }
          },
          { type: "text", text: USER_TEXT }
        ]
      }
    ]
  };

  let data;

  if (window.electron && window.electron.callClaude) {
    data = await window.electron.callClaude(payload);
  } else {
    const apiKey = await getAnthropicApiKey();
    if (!apiKey) throw new Error("Anthropic API key not found");

    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(`Anthropic API error: ${error.error?.message || 'Unknown error'}`);
    }

    data = await response.json();
  }

  const content = data.content[0]?.text;
  return parseAnalysisResponse(content);
}

// ── Public API ─────────────────────────────────────────────────────

export async function analyzeImage(imageUrl: string, systemPrompt?: string): Promise<PatternMatch[]> {
  const provider = await getActiveProvider();
  const hasKey = await hasApiKey(provider);
  if (!hasKey) {
    throw new Error(`${provider === 'anthropic' ? 'Anthropic' : 'OpenAI'} API key not set. Please set an API key to use image analysis.`);
  }

  const prompt = systemPrompt ?? DEFAULT_SYSTEM_PROMPT;

  try {
    const modelId = await resolveModel();

    if (provider === 'anthropic') {
      return await analyzeImageWithClaude(imageUrl, modelId, prompt);
    }
    return await analyzeImageWithOpenAI(imageUrl, modelId, prompt);
  } catch (error) {
    console.error(`Error analyzing image with ${provider}:`, error);
    throw error;
  }
}

/**
 * Analyzes multiple frames from a video and combines the results
 */
export async function analyzeVideoFrames(frameUrls: string[], systemPrompt?: string): Promise<PatternMatch[]> {
  if (!frameUrls || frameUrls.length === 0) {
    throw new Error("No frames provided for analysis");
  }

  const hasKey = await hasApiKey();
  if (!hasKey) {
    throw new Error("API key not set. Please set an API key to use video analysis.");
  }

  try {
    const frameAnalysisPromises = frameUrls.map(frameUrl => analyzeImage(frameUrl, systemPrompt));
    const frameResults = await Promise.all(frameAnalysisPromises);

    const allPatterns: PatternMatch[] = [];
    let combinedContext = '';

    frameResults.forEach(framePatterns => {
      framePatterns.forEach(pattern => {
        allPatterns.push(pattern);
        if (pattern.imageContext && !combinedContext.includes(pattern.imageContext)) {
          combinedContext += (combinedContext ? ' ' : '') + pattern.imageContext;
        }
      });
    });

    if (allPatterns.length === 0) {
      return [];
    }

    const patternMap = new Map<string, { count: number, totalConfidence: number }>();

    allPatterns.forEach(pattern => {
      const name = pattern.name;
      if (!name) return;

      if (!patternMap.has(name)) {
        patternMap.set(name, { count: 0, totalConfidence: 0 });
      }

      const current = patternMap.get(name)!;
      current.count += 1;
      current.totalConfidence += pattern.confidence;
    });

    const combinedPatterns: PatternMatch[] = Array.from(patternMap.entries())
      .map(([name, data]) => ({
        name,
        confidence: data.totalConfidence / data.count,
        imageContext: combinedContext,
        imageSummary: allPatterns[0]?.imageSummary || ''
      }))
      .sort((a, b) => b.confidence - a.confidence)
      .filter(p => p.confidence >= 0.7)
      .slice(0, 10);

    return combinedPatterns;
  } catch (error) {
    console.error("Error analyzing video frames:", error);
    throw error;
  }
}
