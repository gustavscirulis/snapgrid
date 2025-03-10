import { useState, useEffect, RefObject } from 'react';

interface ResizeObserverEntry {
  contentRect: DOMRectReadOnly;
  target: Element;
}

interface ResizeObserverSize {
  width: number | null;
  height: number | null;
}

export function useResizeObserver(ref: RefObject<Element>): ResizeObserverSize {
  const [size, setSize] = useState<ResizeObserverSize>({
    width: null,
    height: null,
  });

  useEffect(() => {
    if (!ref.current) return;

    const observer = new ResizeObserver((entries: ResizeObserverEntry[]) => {
      const { width, height } = entries[0].contentRect;
      setSize({ width, height });
    });

    observer.observe(ref.current);

    return () => {
      observer.disconnect();
    };
  }, [ref]);

  return size;
} 