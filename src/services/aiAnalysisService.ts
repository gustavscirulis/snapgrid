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

  try {
    console.log("Analyzing image, URL type:", imageUrl.substring(0, 30) + "...");

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
      console.log("Using Electron proxy for OpenAI API call");
      data = await window.electron.callOpenAI(apiKey, payload);
    } else {
      console.log("Using fetch API for OpenAI API call");
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

    // Clean up any markdown formatting that might be in the response
    
    console.log("Raw OpenAI content:", content);

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

        console.log("Cleaned JSON string:", jsonString);
        patterns = JSON.parse(jsonString);
      } catch (parseError) {
        console.error("JSON parse error:", parseError);
        // Try a more aggressive cleanup approach
        let jsonString = content.replace(/```/g, '').replace(/json/g, '').trim();
        // Remove any non-JSON text before or after the array
        const arrayMatch = jsonString.match(/\[\s*\{.*\}\s*\]/s);
        if (arrayMatch) {
          jsonString = arrayMatch[0];
        }
        console.log("Second attempt JSON string:", jsonString);
        patterns = JSON.parse(jsonString);
      }

      console.log("Parsed patterns:", patterns);

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