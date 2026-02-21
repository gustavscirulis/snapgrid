import React from "react";
import { Loader2, AlertTriangle } from "lucide-react";
import { ImageItem } from "@/hooks/useImageStore";

interface PatternTagsProps {
  item: ImageItem;
  retryAnalysis?: (imageId: string) => Promise<void>;
}

const PatternTags: React.FC<PatternTagsProps> = ({ item, retryAnalysis }) => {
  if (!item.patterns || item.patterns.length === 0) {
    if (item.isAnalyzing) {
      return (
        <div className="inline-flex items-center gap-1 text-xs text-primary-background bg-secondary px-2 py-1 rounded-md">
          <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
          <span className="text-shine">Analyzing...</span>
        </div>
      );
    }
    if (item.error) {
      return (
        <div
          className="inline-flex items-center gap-1 text-xs text-destructive-foreground bg-destructive/80 px-2 py-1 rounded-md hover:bg-destructive transition-all duration-200 hover:shadow-sm active:bg-destructive/90"
          onClick={(e) => {
            e.stopPropagation();
            if (retryAnalysis) {
              retryAnalysis(item.id);
            }
          }}
          title="Click to retry analysis"
        >
          <AlertTriangle className="w-3 h-3" />
          <span>Analysis failed</span>
        </div>
      );
    }
    return null;
  }

  const isPillClickAnalysisEnabled = localStorage.getItem('dev_enable_pill_click_analysis') === 'true';

  if (item.isAnalyzing) {
    return (
      <div className="flex flex-wrap gap-1">
        <div className="inline-flex items-center gap-1 text-xs text-primary-background bg-secondary px-2 py-1 rounded-md">
          <Loader2 className="w-3 h-3 animate-spin text-muted-foreground" />
          <span className="text-shine">Analyzing...</span>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-wrap gap-1">
      {item.patterns[0]?.imageSummary && (
        <span
          className={`text-xs bg-secondary text-secondary-foreground px-2 py-0.5 rounded-md cursor-default ${
            isPillClickAnalysisEnabled ? 'hover:bg-secondary/90 transition-colors' : ''
          }`}
          title={item.patterns[0]?.imageContext || "Type of interface"}
          onClick={(e) => {
            if (isPillClickAnalysisEnabled) {
              e.stopPropagation();
              if (retryAnalysis) {
                retryAnalysis(item.id);
              }
            }
          }}
        >
          {item.patterns[0]?.imageSummary}
        </span>
      )}
      {item.patterns
        .slice(0, 4)
        .map((pattern, index) => (
        <span
          key={index}
          className={`text-xs bg-secondary text-secondary-foreground px-2 py-0.5 rounded-md cursor-default ${
            isPillClickAnalysisEnabled ? 'hover:bg-secondary/90 transition-colors' : ''
          }`}
          title={`Confidence: ${Math.round(pattern.confidence * 100)}%`}
          onClick={(e) => {
            if (isPillClickAnalysisEnabled) {
              e.stopPropagation();
              if (retryAnalysis) {
                retryAnalysis(item.id);
              }
            }
          }}
        >
          {pattern.name}
        </span>
      ))}
    </div>
  );
};

export default PatternTags;
