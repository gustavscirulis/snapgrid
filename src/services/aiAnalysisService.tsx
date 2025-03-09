try {
    console.log("Analyzing image:", imageUrl);
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify({
        model: "gpt-4-vision-preview",
        messages: [
          {
            role: "user",
            content: [
              {
                type: "text",
                text: "Identify UI design patterns in this image. Return a JSON array with objects containing 'pattern' and 'confidence' (0-1) properties. Include only the top 5 patterns you recognize with the highest confidence."
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
        max_tokens: 300,
      })
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(`OpenAI API error: ${errorData.error?.message || response.statusText}`);
    }

    const data = await response.json();
    const rawResponse = data.choices[0].message.content;
    console.log("OpenAI raw response:", rawResponse);

    // Extract pattern information from response
    let patternData;

    try {
      // Try to parse the response content as JSON
      patternData = JSON.parse(rawResponse);
    } catch (e) {
      console.error("Failed to parse OpenAI response:", e);
      throw new Error("Failed to parse AI response");
    }

    // Map the patterns to the correct format and ensure it's an array
    const mappedPatterns = Array.isArray(patternData) 
      ? patternData.map(p => ({ 
          name: p.pattern || p.name || 'Unknown pattern', 
          confidence: p.confidence || 0.5 
        }))
      : [];

    console.log("Processed patterns:", mappedPatterns);

    // Return the formatted patterns
    return {
      patterns: mappedPatterns
    };
} catch (error) {
    console.error("Error analyzing image:", error);
    // Handle error appropriately, e.g., return an empty array or throw the error
    return { patterns: [] }; 
}