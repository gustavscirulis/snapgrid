
// A service to identify UI patterns in images using deterministic pattern matching
// In a production app, this would connect to a real AI vision service

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

// Simple image analysis rules to better detect patterns
// These are simplified rules - a real system would use computer vision
const PATTERN_KEYWORDS: Record<string, string[]> = {
  "Card Layout": ["card", "container", "box", "panel", "tile", "rect"],
  "Grid System": ["grid", "column", "row", "layout", "table"],
  "Hero Section": ["hero", "banner", "header", "splash", "intro"],
  "Navigation Bar": ["nav", "navbar", "menu", "header", "navigation"],
  "Sidebar": ["sidebar", "side", "panel", "drawer", "off-canvas"],
  "Modal Dialog": ["modal", "dialog", "popup", "overlay", "lightbox"],
  "Form Controls": ["form", "input", "field", "control", "select", "button"],
  "Data Table": ["table", "grid", "data", "column", "row", "cell"],
  "Tabs": ["tab", "panel", "section", "segment", "navigation"],
  "Dropdown Menu": ["dropdown", "menu", "select", "option", "list"],
  "Notification": ["notification", "alert", "toast", "message", "badge"],
  "Carousel": ["carousel", "slider", "gallery", "slideshow", "scroll"],
  "Dark Mode": ["dark", "mode", "theme", "night", "black"],
  "Badge": ["badge", "label", "tag", "pill", "chip", "indicator"],
  "Button": ["button", "btn", "cta", "action", "click"]
};

export async function analyzeImage(imageUrl: string): Promise<PatternMatch[]> {
  // In a real app, this would call a computer vision API
  return new Promise((resolve) => {
    // Simulate API processing time
    setTimeout(() => {
      let patternMatches: PatternMatch[] = [];
      
      // Extract image data for contextual analysis
      const imageData = extractImageContext(imageUrl);
      
      // Look for patterns based on image data
      Object.entries(PATTERN_KEYWORDS).forEach(([pattern, keywords]) => {
        // Check if any keywords match in the image data
        const matchCount = keywords.filter(keyword => 
          imageData.toLowerCase().includes(keyword.toLowerCase())
        ).length;
        
        // If we have matches, include this pattern with a confidence score
        if (matchCount > 0) {
          const confidence = Math.min(0.7 + (matchCount * 0.05), 0.98);
          patternMatches.push({
            pattern,
            confidence: Math.round(confidence * 100) / 100
          });
        }
      });
      
      // If no patterns were detected, use a fallback method
      if (patternMatches.length === 0) {
        // Create a deterministic but seemingly random selection based on the image URL
        let seed = Array.from(imageUrl).reduce((sum, char) => sum + char.charCodeAt(0), 0);
        const shuffled = [...UI_PATTERNS].sort(() => {
          const x = Math.sin(seed++) * 10000;
          return x - Math.floor(x) - 0.5;
        });
        
        // Select 2-4 patterns
        const count = 2 + Math.floor((seed % 3));
        const selectedPatterns = shuffled.slice(0, count);
        
        // Assign confidence scores
        patternMatches = selectedPatterns.map(pattern => ({
          pattern,
          confidence: Math.round((0.7 + Math.random() * 0.3) * 100) / 100 // Between 0.7 and 1.0
        }));
      }
      
      // Sort by confidence
      patternMatches.sort((a, b) => b.confidence - a.confidence);
      
      // Limit to top 5 patterns
      resolve(patternMatches.slice(0, 5));
    }, 500);
  });
}

// Extract content from the image for keyword matching
function extractImageContext(imageUrl: string): string {
  // In a real app, this would perform text extraction or image analysis
  // For now, just extract meaningful parts from the URL to aid in pattern detection
  
  // Extract file name from URL
  const fileName = imageUrl.split('/').pop() || '';
  
  // Check for specific patterns in the image URL
  let context = fileName.replace(/[^a-zA-Z0-9]/g, ' ');
  
  // Add image-specific context based on URL patterns
  if (imageUrl.includes('modal') || imageUrl.includes('dialog')) {
    context += ' modal dialog popup overlay';
  }
  if (imageUrl.includes('card') || imageUrl.includes('tile')) {
    context += ' card layout container box panel';
  }
  if (imageUrl.includes('nav') || imageUrl.includes('menu')) {
    context += ' navigation navbar menu header';
  }
  if (imageUrl.includes('tab')) {
    context += ' tab panel section navigation';
  }
  if (imageUrl.includes('dark') || imageUrl.includes('night')) {
    context += ' dark mode theme night';
  }
  if (imageUrl.includes('carousel') || imageUrl.includes('slider')) {
    context += ' carousel slider gallery slideshow';
  }
  if (imageUrl.includes('button') || imageUrl.includes('btn')) {
    context += ' button btn cta action';
  }
  if (imageUrl.includes('badge') || imageUrl.includes('tag')) {
    context += ' badge label tag pill chip';
  }
  if (imageUrl.includes('grid') || imageUrl.includes('layout')) {
    context += ' grid system column row layout';
  }
  
  // In the demo, we'll check for common UI patterns in the filename
  // This is a simplified approach - real systems would analyze the image
  if (/card|layout|grid|system/i.test(fileName)) {
    context += ' Card Layout Grid System';
  }
  if (/modal|dialog|popup/i.test(fileName)) {
    context += ' Modal Dialog';
  }
  if (/tab|panel/i.test(fileName)) {
    context += ' Tabs';
  }
  if (/badge|tag|pill/i.test(fileName)) {
    context += ' Badge';
  }
  if (/dark|mode|night/i.test(fileName)) {
    context += ' Dark Mode';
  }
  if (/carousel|slider|gallery/i.test(fileName)) {
    context += ' Carousel';
  }
  
  return context;
}
