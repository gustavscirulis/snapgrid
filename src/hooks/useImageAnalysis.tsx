import { useCallback } from "react";
import { analyzeImage, analyzeVideoFrames, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";
import { captureVideoFrames } from '../lib/videoUtils';
import { ImageItem, PatternTag } from "./useImageStore";

export interface UseImageAnalysisReturn {
  analyzeAndUpdateImage: (media: ImageItem, dataUrl: string, savedFilePath?: string) => Promise<ImageItem>;
  retryAnalysis: (imageId: string, images: ImageItem[], updateImageFn: (id: string, updater: (img: ImageItem) => ImageItem) => void) => Promise<void>;
}

export function useImageAnalysis(): UseImageAnalysisReturn {
  const analyzeAndUpdateImage = useCallback(async (
    media: ImageItem, 
    dataUrl: string, 
    savedFilePath?: string
  ): Promise<ImageItem> => {
    // Early return if no API key available
    const hasKey = await hasApiKey();
    if (!hasKey) return media;

    try {
      let analysis;
      let isAnalyzingVideo = false;

      // Handle different media types
      if (media.type === "image") {
        // For images, use the standard analysis
        analysis = await analyzeImage(dataUrl);
      } else if (media.type === "video") {
        // For videos, capture frames and analyze them
        isAnalyzingVideo = true;
        try {
          // Capture frames at 33% and 66% of the video duration
          const frames = await captureVideoFrames(dataUrl);
          // Analyze the captured frames
          analysis = await analyzeVideoFrames(frames);
        } catch (frameError) {
          console.error("Failed to capture or analyze video frames:", frameError);
          throw new Error("Failed to analyze video: " + (frameError instanceof Error ? frameError.message : 'Unknown error'));
        }
      } else {
        // Unsupported media type
        return media;
      }
      
      // Extract the imageContext from the first pattern (should be the same for all patterns)
      const imageContext = analysis[0]?.imageContext || '';
      
      const patternTags = analysis
        .map(pattern => {
          const name = pattern.pattern || pattern.name;
          if (!name) return null;
          
          return { 
            name, 
            confidence: pattern.confidence,
            imageContext: pattern.imageContext,
            imageSummary: pattern.imageSummary
          } as PatternTag;
        })
        .filter((tag): tag is PatternTag => tag !== null);

      const updatedMedia = { 
        ...media, 
        patterns: patternTags, 
        isAnalyzing: false,
        imageContext: imageContext // Set imageContext at the image level
      };

      if (window.electron && savedFilePath) {
        try {
          await window.electron.updateMetadata({
            id: updatedMedia.id,
            metadata: {
              ...updatedMedia,
              filePath: savedFilePath
            }
          });
        } catch (error) {
          console.error("Failed to update metadata:", error);
          toast.error(`Failed to save ${isAnalyzingVideo ? 'video' : 'image'} analysis`);
        }
      }

      return updatedMedia;
    } catch (error) {
      console.error('Media analysis failed:', error);
      toast.error("Analysis failed: " + (error instanceof Error ? error.message : 'Unknown error'));
      
      const updatedMedia = { ...media, isAnalyzing: false, error: 'Analysis failed' };
      
      // Make sure to save the error state in metadata
      if (window.electron && savedFilePath) {
        try {
          await window.electron.updateMetadata({
            id: updatedMedia.id,
            metadata: {
              ...updatedMedia,
              filePath: savedFilePath
            }
          });
        } catch (metadataError) {
          console.error("Failed to update error state metadata:", metadataError);
        }
      }
      
      return updatedMedia;
    }
  }, []);

  const retryAnalysis = useCallback(async (
    imageId: string,
    images: ImageItem[],
    updateImageFn: (id: string, updater: (img: ImageItem) => ImageItem) => void
  ) => {
    // Find the media
    const mediaToAnalyze = images.find(img => img.id === imageId);
    if (!mediaToAnalyze) {
      console.error("Cannot retry analysis: Media not found");
      return;
    }

    // Check if API key exists before attempting retry
    const hasKey = await hasApiKey();
    if (!hasKey) {
      toast.error("OpenAI API key not set. Please set an API key to use image analysis.");
      return;
    }

    // Set analyzing state
    updateImageFn(imageId, (img) => ({ ...img, isAnalyzing: true, error: undefined }));

    try {
      // Get the data URL for analysis
      let dataUrl;
      
      if (mediaToAnalyze.actualFilePath) {
        if (mediaToAnalyze.type === "image") {
          // If we have a file path, convert image to base64
          dataUrl = await window.electron.convertImageToBase64(mediaToAnalyze.actualFilePath);
        } else {
          // For videos, use the file URL directly
          dataUrl = `local-file://${mediaToAnalyze.actualFilePath}`;
        }
      } else if (mediaToAnalyze.url) {
        // Otherwise, use the URL directly (may be a data URL already)
        dataUrl = mediaToAnalyze.url;
      } else {
        throw new Error("No media data available for analysis");
      }
      
      // Perform analysis
      const analyzedMedia = await analyzeAndUpdateImage(mediaToAnalyze, dataUrl, mediaToAnalyze.actualFilePath);
      
      // Update image in the state
      updateImageFn(imageId, () => analyzedMedia);
    } catch (error) {
      console.error("Retry analysis failed:", error);
      
      // Create the updated media with error
      const errorMedia = { ...mediaToAnalyze, isAnalyzing: false, error: 'Analysis failed' };
      
      // Update error state in UI
      updateImageFn(imageId, () => errorMedia);
      
      // Persist error state to disk
      if (window.electron && mediaToAnalyze.actualFilePath) {
        try {
          await window.electron.updateMetadata({
            id: errorMedia.id,
            metadata: {
              ...errorMedia,
              filePath: mediaToAnalyze.actualFilePath
            }
          });
        } catch (metadataError) {
          console.error("Failed to update error state metadata:", metadataError);
        }
      }
    }
  }, [analyzeAndUpdateImage]);

  return {
    analyzeAndUpdateImage,
    retryAnalysis,
  };
}