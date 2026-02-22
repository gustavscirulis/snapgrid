import { useRef, useCallback, useState, useEffect } from "react";

interface RubberBandRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface UseRubberBandOptions {
  scrollContainerRef: React.RefObject<HTMLElement>;
  imageRefs: React.MutableRefObject<Map<string, React.RefObject<HTMLDivElement>>>;
  imageIds: string[];
  onSelectionChange: (ids: Set<string>) => void;
  existingSelection: Set<string>;
}

interface UseRubberBandReturn {
  isActive: boolean;
  rect: RubberBandRect | null;
  handleMouseDown: (e: React.MouseEvent) => void;
}

const DRAG_THRESHOLD = 3; // px before rubber band activates
const SCROLL_SPEED = 10; // px per frame
const SCROLL_ZONE = 50; // px from edge to trigger auto-scroll

function rectsIntersect(
  a: DOMRect,
  b: { left: number; top: number; right: number; bottom: number }
): boolean {
  return !(a.right < b.left || a.left > b.right || a.bottom < b.top || a.top > b.bottom);
}

export function useRubberBand({
  scrollContainerRef,
  imageRefs,
  imageIds,
  onSelectionChange,
  existingSelection,
}: UseRubberBandOptions): UseRubberBandReturn {
  const [isActive, setIsActive] = useState(false);
  const [rect, setRect] = useState<RubberBandRect | null>(null);

  const stateRef = useRef<{
    startX: number;
    startY: number;
    currentX: number;
    currentY: number;
    isActive: boolean;
    frozenSelection: Set<string>;
    scrollAnimFrame: number | null;
    imageIdsSnapshot: string[];
  } | null>(null);

  // Stable ref for imageIds so intersection check uses latest
  const imageIdsRef = useRef(imageIds);
  imageIdsRef.current = imageIds;

  const onSelectionChangeRef = useRef(onSelectionChange);
  onSelectionChangeRef.current = onSelectionChange;

  const computeIntersections = useCallback(() => {
    const state = stateRef.current;
    if (!state || !state.isActive) return;

    const left = Math.min(state.startX, state.currentX);
    const top = Math.min(state.startY, state.currentY);
    const right = Math.max(state.startX, state.currentX);
    const bottom = Math.max(state.startY, state.currentY);

    const bandRect = { left, top, right, bottom };
    const intersected = new Set(state.frozenSelection);

    for (const id of state.imageIdsSnapshot) {
      const ref = imageRefs.current.get(id);
      if (!ref?.current) continue;
      const cardRect = ref.current.getBoundingClientRect();
      if (rectsIntersect(cardRect, bandRect)) {
        intersected.add(id);
      }
    }

    onSelectionChangeRef.current(intersected);
  }, [imageRefs]);

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    // Only start rubber band on left click on grid background
    if (e.button !== 0) return;
    if ((e.target as HTMLElement).closest('.masonry-item')) return;
    // Don't start if clicking interactive elements
    if ((e.target as HTMLElement).closest('button, input, a, [role="menuitem"]')) return;

    const frozen = (e.shiftKey || e.metaKey || e.ctrlKey)
      ? new Set(existingSelection)
      : new Set<string>();

    stateRef.current = {
      startX: e.clientX,
      startY: e.clientY,
      currentX: e.clientX,
      currentY: e.clientY,
      isActive: false,
      frozenSelection: frozen,
      scrollAnimFrame: null,
      imageIdsSnapshot: imageIdsRef.current,
    };

    e.preventDefault();
  }, [existingSelection]);

  // Global mousemove/mouseup listeners
  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const state = stateRef.current;
      if (!state) return;

      state.currentX = e.clientX;
      state.currentY = e.clientY;

      if (!state.isActive) {
        const dx = e.clientX - state.startX;
        const dy = e.clientY - state.startY;
        if (dx * dx + dy * dy < DRAG_THRESHOLD * DRAG_THRESHOLD) return;

        // Activate rubber band
        state.isActive = true;
        setIsActive(true);
        document.body.style.userSelect = 'none';
      }

      // Update visual rect (viewport coordinates)
      const x = Math.min(state.startX, state.currentX);
      const y = Math.min(state.startY, state.currentY);
      const width = Math.abs(state.currentX - state.startX);
      const height = Math.abs(state.currentY - state.startY);
      setRect({ x, y, width, height });

      // Compute which cards intersect
      computeIntersections();

      // Auto-scroll
      const container = scrollContainerRef.current;
      if (container) {
        const containerRect = container.getBoundingClientRect();
        const mouseY = e.clientY;

        if (state.scrollAnimFrame) {
          cancelAnimationFrame(state.scrollAnimFrame);
          state.scrollAnimFrame = null;
        }

        const doAutoScroll = () => {
          const s = stateRef.current;
          if (!s || !s.isActive) return;

          const cr = container.getBoundingClientRect();
          const my = s.currentY;
          let scrolled = false;

          if (my < cr.top + SCROLL_ZONE && container.scrollTop > 0) {
            // Distance into the scroll zone, normalized 0..1
            const intensity = 1 - Math.max(0, my - cr.top) / SCROLL_ZONE;
            container.scrollTop -= Math.ceil(SCROLL_SPEED * intensity);
            scrolled = true;
          } else if (my > cr.bottom - SCROLL_ZONE && container.scrollTop < container.scrollHeight - container.clientHeight) {
            const intensity = 1 - Math.max(0, cr.bottom - my) / SCROLL_ZONE;
            container.scrollTop += Math.ceil(SCROLL_SPEED * intensity);
            scrolled = true;
          }

          if (scrolled) {
            computeIntersections();
            s.scrollAnimFrame = requestAnimationFrame(doAutoScroll);
          }
        };

        if (mouseY < containerRect.top + SCROLL_ZONE || mouseY > containerRect.bottom - SCROLL_ZONE) {
          state.scrollAnimFrame = requestAnimationFrame(doAutoScroll);
        }
      }

      e.preventDefault();
    };

    const handleMouseUp = () => {
      const state = stateRef.current;
      if (!state) return;

      if (state.scrollAnimFrame) {
        cancelAnimationFrame(state.scrollAnimFrame);
      }

      // If rubber band was never activated (click without drag), clear selection
      if (!state.isActive) {
        onSelectionChangeRef.current(state.frozenSelection.size > 0 ? state.frozenSelection : new Set());
      }

      stateRef.current = null;
      setIsActive(false);
      setRect(null);
      document.body.style.userSelect = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [computeIntersections, scrollContainerRef]);

  return {
    isActive,
    rect,
    handleMouseDown,
  };
}
