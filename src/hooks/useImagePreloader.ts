import { useEffect, useRef, useState, useCallback } from 'react';
import { ImageItem } from './useImageStore';

// In-memory cache for loaded images
const imageCache = new Map<string, HTMLImageElement>();
const videoCacheMetadata = new Map<string, { posterLoaded: boolean; videoPreloaded: boolean }>();

// Preload queue to manage loading priority
class PreloadQueue {
  private queue: Array<{ url: string; priority: number }> = [];
  private loading = new Set<string>();
  private maxConcurrent = 50; // Maximum concurrent loading for desktop app
  private onImageLoaded?: (url: string) => void;

  setOnImageLoaded(cb: ((url: string) => void) | undefined) {
    this.onImageLoaded = cb;
  }

  add(url: string, priority: number = 0) {
    if (this.loading.has(url) || imageCache.has(url)) return;

    // Remove existing entry if it exists
    this.queue = this.queue.filter(item => item.url !== url);

    // Add with priority (higher priority loads first)
    this.queue.push({ url, priority });
    this.queue.sort((a, b) => b.priority - a.priority);

    this.processQueue();
  }

  private async processQueue() {
    if (this.loading.size >= this.maxConcurrent || this.queue.length === 0) return;

    const item = this.queue.shift();
    if (!item || imageCache.has(item.url)) return;

    this.loading.add(item.url);

    try {
      await this.preloadImage(item.url);
      this.onImageLoaded?.(item.url);
    } catch (error) {
      console.warn('Failed to preload image:', item.url, error);
    } finally {
      this.loading.delete(item.url);
      this.processQueue(); // Process next item
    }
  }

  private preloadImage(url: string): Promise<void> {
    return new Promise((resolve, reject) => {
      // Skip if already cached
      if (imageCache.has(url)) {
        resolve();
        return;
      }

      const img = new Image();

      // Aggressive preloading settings
      img.loading = 'eager';
      img.fetchpriority = 'high';
      img.decoding = 'async';

      img.onload = async () => {
        // Force decode the image to eliminate decode delay during rendering
        try {
          if ('decode' in img) {
            await img.decode();
          }
        } catch (decodeError) {
          // Decode failed, but image loaded - continue anyway
          console.warn('Image decode failed but loading succeeded:', decodeError);
        }

        imageCache.set(url, img);
        resolve();
      };

      img.onerror = (error) => {
        reject(error);
      };

      // Set crossOrigin for local-file:// protocol support
      img.crossOrigin = 'anonymous';
      img.src = url;
    });
  }

  clear() {
    this.queue = [];
    this.loading.clear();
  }
}

const preloadQueue = new PreloadQueue();

interface UseImagePreloaderOptions {
  rootMargin?: string;
  threshold?: number;
  preloadDistance?: number; // Number of items ahead to preload
}

// Get the URL to preload for an image (prefer thumbnail for grid performance)
function getPreloadUrl(image: ImageItem): string {
  if (image.type === 'image' && image.thumbnailUrl) {
    return image.thumbnailUrl;
  }
  return image.url;
}

export function useImagePreloader(
  images: ImageItem[],
  options: UseImagePreloaderOptions = {}
) {
  const {
    rootMargin = '1500px', // Much larger for masonry grids with tall images
    threshold = 0.01,
  } = options;

  const [loadedImages, setLoadedImages] = useState<Set<string>>(new Set());
  const [visibleImages, setVisibleImages] = useState<Set<string>>(new Set());
  const observerRef = useRef<IntersectionObserver | null>(null);
  const elementRefs = useRef<Map<string, Element>>(new Map());

  // Refs so observer callback always sees latest state without re-creating observer
  const loadedImagesRef = useRef(loadedImages);
  loadedImagesRef.current = loadedImages;
  const visibleImagesRef = useRef(visibleImages);
  visibleImagesRef.current = visibleImages;
  const imagesRef = useRef(images);
  imagesRef.current = images;

  // Check if image is already cached
  const isImageCached = useCallback((url: string) => {
    return imageCache.has(url);
  }, []);

  // Get cached image
  const getCachedImage = useCallback((url: string) => {
    return imageCache.get(url);
  }, []);

  // Preload images with priority
  const preloadImage = useCallback((url: string, priority: number = 0) => {
    if (!url || url.startsWith('data:')) return Promise.resolve();

    if (imageCache.has(url)) {
      return Promise.resolve();
    }

    preloadQueue.add(url, priority);
    return Promise.resolve();
  }, []);

  // Preload video poster
  const preloadVideoPoster = useCallback((item: ImageItem, priority: number = 0) => {
    if (item.type !== 'video' || !item.posterUrl) return Promise.resolve();

    const metadata = videoCacheMetadata.get(item.id) || { posterLoaded: false, videoPreloaded: false };

    if (!metadata.posterLoaded) {
      preloadQueue.add(item.posterUrl, priority);
      videoCacheMetadata.set(item.id, { ...metadata, posterLoaded: true });
    }

    return Promise.resolve();
  }, []);

  // Event-driven: update loadedImages when PreloadQueue finishes loading an image
  useEffect(() => {
    preloadQueue.setOnImageLoaded((url: string) => {
      const currentImages = imagesRef.current;
      const matchingIds = currentImages
        .filter(img => getPreloadUrl(img) === url || img.posterUrl === url)
        .map(img => img.id);

      if (matchingIds.length > 0) {
        setLoadedImages(prev => {
          const next = new Set(prev);
          matchingIds.forEach(id => next.add(id));
          return next;
        });
      }
    });

    return () => preloadQueue.setOnImageLoaded(undefined);
  }, []); // Stable — uses imagesRef

  // Setup intersection observer (stable — uses refs, not state, in callback)
  useEffect(() => {
    observerRef.current = new IntersectionObserver(
      (entries) => {
        const newVisibleImages = new Set(visibleImagesRef.current);
        const newLoadedImages = new Set(loadedImagesRef.current);
        const currentImages = imagesRef.current;

        entries.forEach((entry) => {
          const imageId = entry.target.getAttribute('data-image-id');
          if (!imageId) return;

          if (entry.isIntersecting) {
            newVisibleImages.add(imageId);

            // Find the image
            const image = currentImages.find(img => img.id === imageId);
            if (!image) return;

            // Since we preload everything, just ensure this image is prioritized
            if (image.type === 'video') {
              preloadVideoPoster(image, 15);
            } else {
              preloadImage(getPreloadUrl(image), 15);
            }

            // Mark as loaded if cached
            if (image.type === 'image' && imageCache.has(getPreloadUrl(image))) {
              newLoadedImages.add(imageId);
            } else if (image.type === 'video' && image.posterUrl && imageCache.has(image.posterUrl)) {
              newLoadedImages.add(imageId);
            }
          } else {
            newVisibleImages.delete(imageId);
          }
        });

        setVisibleImages(newVisibleImages);
        setLoadedImages(newLoadedImages);
      },
      {
        rootMargin,
        threshold
      }
    );

    // Re-observe all currently tracked elements
    elementRefs.current.forEach((element, imageId) => {
      element.setAttribute('data-image-id', imageId);
      observerRef.current!.observe(element);
    });

    return () => {
      if (observerRef.current) {
        observerRef.current.disconnect();
      }
    };
  }, [rootMargin, threshold, preloadImage, preloadVideoPoster]);

  // Observe elements
  const observeElement = useCallback((element: Element, imageId: string) => {
    if (!observerRef.current) return;

    element.setAttribute('data-image-id', imageId);
    elementRefs.current.set(imageId, element);
    observerRef.current.observe(element);
  }, []);

  // Unobserve elements
  const unobserveElement = useCallback((imageId: string) => {
    if (!observerRef.current) return;

    const element = elementRefs.current.get(imageId);
    if (element) {
      observerRef.current.unobserve(element);
      elementRefs.current.delete(imageId);
    }
  }, []);

  // Preload ALL images - immediate and aggressive
  useEffect(() => {
    if (images.length === 0) return;

    // Start preloading immediately without waiting
    const startPreload = () => {
      images.forEach((image, index) => {
        // Higher priority for earlier images (visible first)
        const priority = Math.max(0, 100 - index); // Higher base priority

        if (image.type === 'video') {
          preloadVideoPoster(image, priority);
        } else {
          preloadImage(getPreloadUrl(image), priority);
        }
      });
    };

    // Start immediately
    startPreload();

    // Also start in next tick for any missed images
    setTimeout(startPreload, 0);
  }, [images, preloadImage, preloadVideoPoster]);

  // Clear cache when images change significantly
  useEffect(() => {
    const currentImageUrls = new Set(images.map(img => getPreloadUrl(img)));

    // Remove cached images that are no longer in the list
    for (const [url] of imageCache) {
      if (!currentImageUrls.has(url)) {
        imageCache.delete(url);
      }
    }

    // Clean up video metadata
    const currentImageIds = new Set(images.map(img => img.id));
    for (const [id] of videoCacheMetadata) {
      if (!currentImageIds.has(id)) {
        videoCacheMetadata.delete(id);
      }
    }
  }, [images]);

  return {
    observeElement,
    unobserveElement,
    isImageLoaded: (imageId: string) => loadedImages.has(imageId),
    isImageVisible: (imageId: string) => visibleImages.has(imageId),
    isImageCached,
    getCachedImage,
    preloadImage,
    // Clear all caches (useful for memory management)
    clearCache: () => {
      imageCache.clear();
      videoCacheMetadata.clear();
      preloadQueue.clear();
      setLoadedImages(new Set());
      setVisibleImages(new Set());
    }
  };
}
