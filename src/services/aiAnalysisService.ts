
// A service to identify UI patterns in images using OpenAI's Vision API

interface PatternMatch {
  pattern: string;
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

// OpenAI API configuration
let apiKey = '';

export function setOpenAIApiKey(key: string): void {
  apiKey = key;
}

export function hasApiKey(): boolean {
  return !!apiKey;
}

export async function analyzeImage(imageUrl: string): Promise<PatternMatch[]> {
  if (!apiKey) {
    throw new Error("OpenAI API key not set. Please set an API key to use image analysis.");
  }
  
  // Convert local file paths to base64 if needed
  if (imageUrl.startsWith('local-file://') || imageUrl.startsWith('file://')) {
    try {
      // For Electron apps, we need to use a data URL instead of file path
      console.log("Local file detected, converting to base64");
      // We'll use a placeholder data URL since we can't read the file directly
      // This should be replaced with actual image data in production
      if (window.electron) {
        // Request the image as base64 from Electron main process
        const base64Data = await window.electron.convertImageToBase64(imageUrl);
        imageUrl = base64Data;
      } else {
        throw new Error("Cannot access local files without Electron");
      }
    } catch (error) {
      console.error("Error converting local file to base64:", error);
      throw new Error("Failed to convert local file to base64 for analysis");
    }
  }

  try {
    console.log("Analyzing image, URL type:", imageUrl.substring(0, 30) + "...");
    
    // Prepare the API request to OpenAI
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
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
      })
    });

    if (!response.ok) {
      const error = await response.json();
      console.error("OpenAI API error:", error);
      throw new Error(`OpenAI API error: ${error.error?.message || 'Unknown error'}`);
    }

    const data = await response.json();
    let content = data.choices[0]?.message?.content;
    
    // Clean up any markdown formatting that might be in the response
    content = content.replace(/```json|```|`/g, '').trim();
    
    console.log("OpenAI raw response:", content);

    // Parse the JSON response from OpenAI
    try {
      let patterns: PatternMatch[] = JSON.parse(content);
      
      // Validate and clean up the response
      if (Array.isArray(patterns)) {
        patterns = patterns
          .filter(p => p && p.pattern && typeof p.confidence === 'number')
          .map(p => ({
            pattern: p.pattern,
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
