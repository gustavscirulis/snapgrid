// A service to identify UI patterns in images using OpenAI's Vision API

interface PatternMatch {
  pattern?: string;
  name?: string;
  confidence: number;
}

// Common UI design patterns to detect
const UI_PATTERNS = [
  "Card Layout",
  "Grid System",
  "Hero Section",
  "Navigation Bar",
  "Sidebar",
  "Modal Dialog",
  "Form Controls",
  "Data Table",
  "Tabs",
  "Dropdown Menu",
  "Notification",
  "Carousel",
  "Progress Indicator",
  "Timeline",
  "Avatar",
  "Badge",
  "Button",
  "Icon Set",
  "Typography System",
  "Color System",
  "Dark Mode",
  "Mobile Layout",
  "Responsive Design",
  "Material Design",
  "Glassmorphism",
  "Neumorphism",
  "Minimalist UI"
];

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
          content: "You are an AI specialized in UI/UX design pattern recognition. Analyze the image and identify common UI patterns present in it. Focus on design elements, layouts, and components."
        },
        {
          role: "user",
          content: [
            {
              type: "text",
              text: "Analyze this UI design image and identify the UI patterns present. Return only the top 5 patterns you can identify with a confidence score from 0 to 1. Format your response as a strict valid JSON array with 'pattern' and 'confidence' fields only, no markdown formatting, no code block symbols."
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
      max_tokens: 300
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

        patterns = JSON.parse(jsonString);
      } catch (parseError) {
        // Try a more aggressive cleanup approach
        let jsonString = content.replace(/```/g, '').replace(/json/g, '').trim();
        // Remove any non-JSON text before or after the array
        const arrayMatch = jsonString.match(/\[\s*\{.*\}\s*\]/s);
        if (arrayMatch) {
          jsonString = arrayMatch[0];
        }
        patterns = JSON.parse(jsonString);
      }


      // Validate and clean up the response
      if (Array.isArray(patterns)) {
        patterns = patterns
          .filter(p => p && (p.pattern || p.name) && typeof p.confidence === 'number')
          .map(p => ({
            name: p.pattern || p.name, // Map 'pattern' field to 'name' as expected by the UI
            confidence: Math.min(Math.max(p.confidence, 0), 1) // Ensure confidence is between 0 and 1
          }))
          .slice(0, 5); // Limit to top 5

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