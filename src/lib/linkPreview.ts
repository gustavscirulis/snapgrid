// Utility to fetch og:image and favicon for a URL
export async function fetchLinkPreview(url: string): Promise<{ ogImageUrl?: string; faviconUrl?: string; title?: string; description?: string }> {
  // Use Electron IPC if available
  if (typeof window !== 'undefined' && (window as any).electron?.fetchLinkPreview) {
    return await (window as any).electron.fetchLinkPreview(url);
  }
  // Fallback for browser (returns empty)
  return {};
}
