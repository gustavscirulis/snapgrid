// A service to identify UI patterns in images using OpenAI's Vision API

interface PatternMatch {
  pattern?: string;
  name?: string;
  confidence: number;
}

// API key handling functions
export async function setOpenAIApiKey(key: string): Promise<boolean> {
  try {
    if (window.electron && window.electron.setApiKey) {
      // Use secure storage in Electron
      const result = await window.electron.setApiKey('openai', key);
      return result.success;
    } else {
      // Fallback to localStorage for web version
      localStorage.setItem("openai-api-key", key);
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
      return result.success;
    } else {
      // Fallback to localStorage for web version
      localStorage.removeItem("openai-api-key");
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
    const payload = {
      model: "gpt-4o", // Using GPT-4o which supports vision
      messages: [
        {
          role: "system",
          content: "You are an expert AI in UI/UX design pattern recognition. Your task is to analyze visual interfaces and identify commonly used UI design patterns based on layout, components, and design structure."
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Review this UI design image and extract the top 10 recognizable UI patterns. For each pattern, include a confidence score between 0 and 1. Respond with a strict, valid JSON array containing only 'pattern' and 'confidence' fields. Do not include markdown formatting, explanations, or code block symbols. Use title case."
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
      console.log("Using fetch API for OpenAI API call");
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

        // Handle potential truncated JSON by checking and fixing incomplete items
        const lastBraceIndex = jsonString.lastIndexOf('}');
        const lastBracketIndex = jsonString.lastIndexOf(']');
        
        if (lastBraceIndex > lastBracketIndex) {
          // JSON might be truncated - fix by adding closing bracket
          jsonString = jsonString.substring(0, lastBraceIndex + 1) + ']';
        }
        
        patterns = JSON.parse(jsonString);
      } catch (parseError) {
        // Try a more aggressive cleanup approach
        let jsonString = content.replace(/```/g, '').replace(/json/g, '').trim();
        
        // Remove any non-JSON text before or after the array
        const arrayMatch = jsonString.match(/\[\s*\{.*\}\s*\]/s);
        if (arrayMatch) {
          jsonString = arrayMatch[0];
        } else {
          // Handle truncated JSON by finding the last complete object
          const matches = jsonString.match(/\{[^{}]*\}/g);
          if (matches && matches.length > 0) {
            jsonString = '[' + matches.join(',') + ']';
          }
        }
        
        patterns = JSON.parse(jsonString);
      }


      // Validate and clean up the response
      if (Array.isArray(patterns)) {
        patterns = patterns
          .filter(p => p && (p.pattern || p.name) && typeof p.confidence === 'number' && p.confidence >= 0.7)
          .map(p => ({
            name: p.pattern || p.name, // Map 'pattern' field to 'name' as expected by the UI
            confidence: Math.min(Math.max(p.confidence, 0), 1) // Ensure confidence is between 0 and 1
          }))
          .sort((a, b) => b.confidence - a.confidence) // Sort by confidence score
          .slice(0, 10); // Keep up to 10 patterns for searching but only display top 5 in UI

        return patterns;
      }
      throw new Error('Invalid response format from OpenAI');
    } catch (e) {
      console.error("Failed to parse OpenAI response:", e, content);
      throw new Error('Failed to parse response from OpenAI');
    }
  } catch (error) {
    console.error("Error analyzing image with OpenAI:", error);
    throw error; // Rethrow to handle in the UI
  }
}