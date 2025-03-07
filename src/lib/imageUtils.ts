export function validateImageFile(file: File): boolean {
  // Check if the file is an image
  if (!file.type.match('image.*')) {
    return false;
  }
  
  // Check file size (max 10MB)
  const maxSize = 10 * 1024 * 1024; // 10MB
  if (file.size > maxSize) {
    return false;
  }
  
  return true;
}

export function getImageDimensions(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resolve({
        width: img.width,
        height: img.height,
      });
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
  });
}

export function calculateGridRowSpan(height: number, width: number, gridRowHeight = 10): number {
  // Calculate aspect ratio and determine how many grid rows the image should span
  const aspectRatio = height / width;
  const baseWidth = 300; // This should match the minmax value in CSS
  const imageHeight = baseWidth * aspectRatio;
  return Math.ceil(imageHeight / gridRowHeight) + 1; // +1 for some padding
}

// Animation utilities for smooth image transitions
export function getThumbnailPosition(element: HTMLElement | null): {
  left: number;
  top: number;
  width: number;
  height: number;
} {
  if (!element) {
    return { left: 0, top: 0, width: 0, height: 0 };
  }
  
  const rect = element.getBoundingClientRect();
  return {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

export function getScaleTransform(startPos: { 
  left: number; 
  top: number; 
  width: number; 
  height: number;
}, targetElement: HTMLElement | null): string {
  if (!targetElement) {
    return 'scale(1)';
  }
  
  const targetRect = targetElement.getBoundingClientRect();
  const scaleX = startPos.width / targetRect.width;
  const scaleY = startPos.height / targetRect.height;
  
  const translateX = startPos.left - targetRect.left;
  const translateY = startPos.top - targetRect.top;
  
  return `translate(${translateX}px, ${translateY}px) scale(${scaleX}, ${scaleY})`;
}
