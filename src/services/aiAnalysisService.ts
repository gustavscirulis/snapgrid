// A service to identify UI patterns in images using OpenAI's Vision API
import { sendAnalyticsEvent } from "@/services/analyticsService";

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

// API key handling functions
export async function setOpenAIApiKey(key: string): Promise<boolean> {
  try {
    if (window.electron && window.electron.setApiKey) {
      // Use secure storage in Electron
      const result = await window.electron.setApiKey('openai', key);
      
      if (result.success) {
        // Send analytics event when key is added successfully
        sendAnalyticsEvent('api-key-added', { service: 'openai' });
      }
      
      return result.success;
    } else {
      // Fallback to localStorage for web version
      localStorage.setItem("openai-api-key", key);
      
      // Send analytics event when key is added successfully
      sendAnalyticsEvent('api-key-added', { service: 'openai' });
      
      return true;
    }
  } catch (error) {
    console.error("Error storing API key:", error);
    return false;
  }
}

export async function hasApiKey(): Promise<boolean> {
  try {
    if (window.electron && window.electron.hasApiKey) {
      // Check secure storage in Electron
      const result = await window.electron.hasApiKey('openai');
      return result.success && result.hasKey;
    } else {
      // Fallback to localStorage for web version
      return !!localStorage.getItem("openai-api-key");
    }
  } catch (error) {
    console.error("Error checking API key:", error);
    return false;
  }
}

export async function getApiKey(): Promise<string | null> {
  try {
    if (window.electron && window.electron.getApiKey) {
      // Get from secure storage in Electron
      const result = await window.electron.getApiKey('openai');
      return result.success ? result.key : null;
    } else {
      // Fallback to localStorage for web version
      return localStorage.getItem("openai-api-key");
    }
  } catch (error) {
    console.error("Error retrieving API key:", error);
    return null;
  }
}

export async function deleteApiKey(): Promise<boolean> {
  try {
    if (window.electron && window.electron.deleteApiKey) {
      // Delete from secure storage in Electron
      const result = await window.electron.deleteApiKey('openai');
      
      if (result.success) {
        // Send analytics event when key is removed successfully
        sendAnalyticsEvent('api-key-removed', { service: 'openai' });
      }
      
      return result.success;
    } else {
      // Fallback to localStorage for web version
      localStorage.removeItem("openai-api-key");
      
      // Send analytics event when key is removed successfully
      sendAnalyticsEvent('api-key-removed', { service: 'openai' });
      
      return true;
    }
  } catch (error) {
    console.error("Error deleting API key:", error);
    return false;
  }
}

export async function analyzeImage(imageUrl: string): Promise<PatternMatch[]> {
  // Check if API key exists
  const hasKey = await hasApiKey();
  if (!hasKey) {
    throw new Error("OpenAI API key not set. Please set an API key to use image analysis.");
  }

  try {
    // Prepare the request payload
    const prompt = `You are an expert AI in analyzing images. Your task is to analyze the content of images and provide appropriate descriptions based on whether they contain UI interfaces or general scenes.
    
    Provide your response in the following JSON format:
    {
      "imageContext": "Detailed description of the entire image, including its purpose and main characteristics",
      "imageSummary": "Very brief summary (1-2 words) of the main content or purpose",
      "patterns": [
        {
          "name": "Specific UI component/pattern name OR main object/subject",
          "confidence": 0.95
        }
      ]
    }

    Guidelines:
      1. The "imageSummary" should be a very brief (1-2 words) description of what the image shows
      2. The "imageContext" should provide detailed information about the entire image
      3. For UI images:
         - List specific UI design components and UX patterns
         - Use technical UI/UX terminology
         - Each pattern should be 1-2 words maximum, not duplicative of imageSummary
      4. For non-UI images:
         - List main objects, subjects, or elements
         - Focus on what is visually prominent
         - Use descriptive, non-technical language
      5. Include confidence scores between 0.8 and 1.0
      6. List patterns in order of confidence/importance
      7. Ensure that the patterns are unique and not duplicates of each other and imageSummary
      7. Provide exactly 6 patterns, ordered by confidence`;

    const payload = {
      model: "gpt-4.1-mini",
      messages: [
        {
          role: "system",
          content: prompt
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Analyze this image and provide a detailed breakdown of its content. If it's a UI screenshot, focus on UI patterns and components. If it's a general scene, focus on objects and subjects. Respond with a strict, valid JSON object in the format specified in the system prompt. Do not include markdown formatting, explanations, or code block symbols. Use title case for pattern/object names. Provide up to 6 patterns/objects, ordered by confidence."
            },
            {
              type: "image_url",
              image_url: {
                url: imageUrl
              }
            }
          ]
        }
      ],
      max_tokens: 800
    };

    let data;

    // Try to use Electron proxy if available, otherwise fall back to fetch
    if (window.electron && window.electron.callOpenAI) {
      // In Electron mode, API key is handled securely on the main process side
      data = await window.electron.callOpenAI(payload);
    } else {
      // In web mode, use fetch with API key from localStorage
      const apiKey = await getApiKey();
      
      if (!apiKey) {
        throw new Error("API key not found");
      }
      
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
        console.error("OpenAI API error:", error);
        throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
      }

      data = await response.json();
    }

    let content = data.choices[0]?.message?.content;

    // Parse the JSON response from OpenAI
    try {
      let patterns;
      try {
        // Try to parse the JSON response
        // Note: The response could be a string of JSON or have markdown formatting
        let jsonString = content;

        // Clean up common markdown formatting
        if (content.includes('```json')) {
          jsonString = content.split('```json')[1].split('```')[0].trim();
        } else if (content.includes('```')) {
          jsonString = content.split('```')[1].split('```')[0].trim();
        }
        
        const response = JSON.parse(jsonString) as AnalysisResponse;
        
        // Validate and clean up the response
        if (response.patterns && Array.isArray(response.patterns)) {
          // Get all patterns for search (up to 6)
          const allPatterns = response.patterns
            .filter(p => p && p.name && typeof p.confidence === 'number' && p.confidence >= 0.7)
            .map(p => ({
              name: p.name,
              confidence: Math.min(Math.max(p.confidence, 0), 1),
              imageContext: response.imageContext,
              imageSummary: response.imageSummary
            }))
            .sort((a, b) => b.confidence - a.confidence)
            .slice(0, 6); // Keep all 6 patterns for search

          return allPatterns;
        }
        throw new Error('Invalid response format from OpenAI');
      } catch (parseError) {
        // Try a more aggressive cleanup approach
        let jsonString = content.replace(/```/g, '').replace(/json/g, '').trim();
        
        // Remove any non-JSON text before or after the object
        const objectMatch = jsonString.match(/\{[\s\S]*\}/);
        if (objectMatch) {
          jsonString = objectMatch[0];
        }
        
        const response = JSON.parse(jsonString) as AnalysisResponse;
        
        if (response.patterns && Array.isArray(response.patterns)) {
          // Get all patterns for search (up to 6)
          const allPatterns = response.patterns
            .filter(p => p && p.name && typeof p.confidence === 'number' && p.confidence >= 0.7)
            .map(p => ({
              name: p.name,
              confidence: Math.min(Math.max(p.confidence, 0), 1),
              imageContext: response.imageContext,
              imageSummary: response.imageSummary
            }))
            .sort((a, b) => b.confidence - a.confidence)
            .slice(0, 6); // Keep all 6 patterns for search

          return allPatterns;
        }
        throw new Error('Invalid response format from OpenAI');
      }
    } catch (e) {
      console.error("Failed to parse OpenAI response:", e, content);
      throw new Error('Failed to parse response from OpenAI');
    }
  } catch (error) {
    console.error("Error analyzing image with OpenAI:", error);
    throw error; // Rethrow to handle in the UI
  }
}

/**
 * Analyzes multiple frames from a video and combines the results
 * @param frameUrls Array of data URLs for video frames
 * @returns Promise resolving to combined pattern matches
 */
export async function analyzeVideoFrames(frameUrls: string[]): Promise<PatternMatch[]> {
  if (!frameUrls || frameUrls.length === 0) {
    throw new Error("No frames provided for analysis");
  }

  // Check if API key exists
  const hasKey = await hasApiKey();
  if (!hasKey) {
    throw new Error("OpenAI API key not set. Please set an API key to use video analysis.");
  }

  try {
    // Analyze each frame separately
    const frameAnalysisPromises = frameUrls.map(frameUrl => analyzeImage(frameUrl));
    const frameResults = await Promise.all(frameAnalysisPromises);

    // Combine results from all frames
    const allPatterns: PatternMatch[] = [];
    let combinedContext = '';

    // First, collect all patterns from all frames
    frameResults.forEach(framePatterns => {
      framePatterns.forEach(pattern => {
        allPatterns.push(pattern);
        
        // Collect context descriptions to combine later
        if (pattern.imageContext && !combinedContext.includes(pattern.imageContext)) {
          combinedContext += (combinedContext ? ' ' : '') + pattern.imageContext;
        }
      });
    });

    // If we don't have any patterns, return empty array
    if (allPatterns.length === 0) {
      return [];
    }

    // Group patterns by name and calculate average confidence
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
    
    // Create final pattern list with averaged confidences
    const combinedPatterns: PatternMatch[] = Array.from(patternMap.entries())
      .map(([name, data]) => ({
        name,
        confidence: data.totalConfidence / data.count,
        imageContext: combinedContext,
        imageSummary: allPatterns[0]?.imageSummary || ''
      }))
      .sort((a, b) => b.confidence - a.confidence) // Sort by confidence score
      .filter(p => p.confidence >= 0.7) // Keep only patterns with confidence >= 0.7
      .slice(0, 10); // Keep only top 10 patterns
      
    return combinedPatterns;
  } catch (error) {
    console.error("Error analyzing video frames with OpenAI:", error);
    throw error; // Rethrow to handle in the UI
  }
}