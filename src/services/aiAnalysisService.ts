
// A simple service to identify UI patterns in images
// In a production app, this could be connected to a real AI service

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

export async function analyzeImage(imageUrl: string): Promise<PatternMatch[]> {
  // This is a mock implementation that randomly selects 2-4 patterns
  // In a real app, this would call an AI service API
  
  return new Promise((resolve) => {
    // Simulate API processing time
    setTimeout(() => {
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
      const results = selectedPatterns.map(pattern => ({
        pattern,
        confidence: Math.round((0.7 + Math.random() * 0.3) * 100) / 100 // Between 0.7 and 1.0
      }));
      
      resolve(results);
    }, 500);
  });
}
