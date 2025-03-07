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

// Get position and dimensions of an element
export function getElementPosition(element: HTMLElement | null): {
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
    left: rect.left + window.scrollX,
    top: rect.top + window.scrollY,
    width: rect.width,
    height: rect.height,
  };
}

// Calculate the transform values for thumbnail-to-fullscreen animation
export function calculateAnimationStyles(
  sourceElement: HTMLElement | null,
  targetElement: HTMLElement | null
): { transform: string; opacity: number } {
  if (!sourceElement || !targetElement) {
    return { transform: 'none', opacity: 1 };
  }

  const sourceRect = sourceElement.getBoundingClientRect();
  const targetRect = targetElement.getBoundingClientRect();
  
  // Calculate scale
  const scaleX = sourceRect.width / targetRect.width;
  const scaleY = sourceRect.height / targetRect.height;
  
  // Calculate translation
  const translateX = (sourceRect.left - targetRect.left) + (sourceRect.width - targetRect.width * scaleX) / 2;
  const translateY = (sourceRect.top - targetRect.top) + (sourceRect.height - targetRect.height * scaleY) / 2;
  
  return {
    transform: `translate(${translateX}px, ${translateY}px) scale(${scaleX}, ${scaleY})`,
    opacity: 1
  };
}
