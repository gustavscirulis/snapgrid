import { useState, useEffect, useRef } from "react";
import { hasApiKey } from "@/services/aiAnalysisService";
import { ImageItem } from "./useImageStore";

interface UseApiKeyWatcherOptions {
  settingsOpen: boolean;
  images: ImageItem[];
  retryAnalysis?: (imageId: string) => Promise<void>;
}

export function useApiKeyWatcher({ settingsOpen, images, retryAnalysis }: UseApiKeyWatcherOptions) {
  const [hasOpenAIKey, setHasOpenAIKey] = useState<boolean | null>(null);
  const [previousKeyStatus, setPreviousKeyStatus] = useState<boolean | null>(null);

  // Ref for current images so the batch analysis loop captures a snapshot
  // without re-triggering the effect on every image change
  const imagesRef = useRef(images);
  imagesRef.current = images;

  // Ref for aborting batch analysis if component unmounts or key changes
  const analyzeAbortRef = useRef<AbortController | null>(null);

  // Check if the OpenAI API key is set on mount
  useEffect(() => {
    const checkApiKey = async () => {
      const exists = await hasApiKey();
      setHasOpenAIKey(exists);
    };
    checkApiKey();
  }, []);

  // Recheck API key when settings panel closes
  useEffect(() => {
    if (settingsOpen === false) {
      const checkApiKey = async () => {
        const exists = await hasApiKey();
        setHasOpenAIKey(exists);
      };
      checkApiKey();
    }
  }, [settingsOpen]);

  // Analyze all unanalyzed images when API key is newly set
  useEffect(() => {
    if (previousKeyStatus !== true && hasOpenAIKey === true && retryAnalysis) {
      const imagesToAnalyze = imagesRef.current.filter(img =>
        (!img.patterns || img.patterns.length === 0) &&
        !img.isAnalyzing &&
        !img.error
      );

      if (imagesToAnalyze.length > 0) {
        analyzeAbortRef.current?.abort();
        const controller = new AbortController();
        analyzeAbortRef.current = controller;

        const analyzeQueue = async () => {
          for (const image of imagesToAnalyze) {
            if (controller.signal.aborted) return;
            try {
              await retryAnalysis(image.id);
            } catch (err) {
              console.error(`Analysis failed for ${image.id}:`, err);
            }
            if (controller.signal.aborted) return;
            await new Promise(resolve => setTimeout(resolve, 300));
          }
        };

        analyzeQueue();
      }
    }

    setPreviousKeyStatus(hasOpenAIKey);

    return () => {
      analyzeAbortRef.current?.abort();
    };
  }, [hasOpenAIKey, retryAnalysis, previousKeyStatus]);

  return { hasOpenAIKey };
}
