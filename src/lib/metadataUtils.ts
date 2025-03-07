
/**
 * Utility functions for fetching metadata from URLs
 */

interface UrlMetadata {
  title?: string;
  description?: string;
  imageUrl?: string;
  faviconUrl?: string;
}

export async function fetchUrlMetadata(url: string): Promise<UrlMetadata> {
  try {
    // Create a proxy URL to avoid CORS issues
    const proxyUrl = `https://api.allorigins.win/get?url=${encodeURIComponent(url)}`;
    
    const response = await fetch(proxyUrl);
    const data = await response.json();
    
    if (!data.contents) {
      throw new Error('Failed to fetch URL contents');
    }
    
    const parser = new DOMParser();
    const doc = parser.parseFromString(data.contents, 'text/html');
    
    // Extract metadata
    const metadata: UrlMetadata = {};
    
    // Title
    metadata.title = doc.querySelector('meta[property="og:title"]')?.getAttribute('content') || 
                     doc.querySelector('title')?.textContent || 
                     url;
    
    // Description
    metadata.description = doc.querySelector('meta[property="og:description"]')?.getAttribute('content') || 
                          doc.querySelector('meta[name="description"]')?.getAttribute('content') || 
                          '';
    
    // Image
    metadata.imageUrl = doc.querySelector('meta[property="og:image"]')?.getAttribute('content') || 
                       doc.querySelector('meta[property="twitter:image"]')?.getAttribute('content');
    
    // Favicon
    const domain = new URL(url).hostname;
    metadata.faviconUrl = `https://www.google.com/s2/favicons?domain=${domain}&sz=128`;
    
    return metadata;
  } catch (error) {
    console.error('Error fetching URL metadata:', error);
    
    // Fallback to basic metadata
    const domain = new URL(url).hostname;
    return {
      title: domain,
      faviconUrl: `https://www.google.com/s2/favicons?domain=${domain}&sz=128`
    };
  }
}
