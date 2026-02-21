import React from "react";
import { Key, Upload } from "lucide-react";
import { Button } from "@/components/ui/button";
import { motion } from "framer-motion";

interface EmptyStateCardProps {
  hasOpenAIKey: boolean | null;
  isDragging: boolean;
  onOpenSettings?: () => void;
}

const EmptyStateCard: React.FC<EmptyStateCardProps> = ({ hasOpenAIKey, isDragging, onOpenSettings }) => {
  return (
    <motion.div
      className={`bg-white/95 dark:bg-zinc-900/95 backdrop-blur-sm shadow-2xl rounded-xl w-full overflow-hidden pointer-events-auto border border-gray-200 dark:border-zinc-800 transition-all duration-300 ${
        isDragging ? 'opacity-80 blur-[1px]' : 'opacity-100'
      }`}
    >
      {hasOpenAIKey === null ? (
        <div className="p-6">
          <div className="animate-pulse flex space-x-4">
            <div className="flex-1 space-y-4 py-1">
              <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4"></div>
              <div className="space-y-2">
                <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded"></div>
                <div className="h-4 bg-gray-200 dark:bg-gray-700 rounded w-5/6"></div>
              </div>
            </div>
          </div>
        </div>
      ) : hasOpenAIKey ? (
        <>
          <div className="p-8 select-none">
            <div className="rounded-full bg-gray-100 dark:bg-zinc-800 w-14 h-14 flex items-center justify-center mb-5">
              <Upload className="h-7 w-7 text-gray-600 dark:text-gray-400" />
            </div>
            <h3 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-3">
              Drag and drop images or videos here
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400 mb-4">
              They will be automatically analysed for UI patterns and organised.
            </p>
          </div>
          <div className="bg-gray-50 dark:bg-zinc-800/50 px-6 py-4 border-t border-gray-200 dark:border-zinc-800 select-none">
            <p className="text-xs text-gray-700 dark:text-gray-300">
              You can also paste images from clipboard (⌘+V)
            </p>
          </div>
        </>
      ) : (
        <>
          <div className="p-8 select-none">
            <div className="rounded-full bg-gray-100 dark:bg-zinc-800 w-14 h-14 flex items-center justify-center mb-5">
              <Key className="h-7 w-7 text-gray-600 dark:text-gray-400" />
            </div>
            <h3 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-3">
              Add an OpenAI API key
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-400 mb-6">
              Unlock automatic pattern detection in screenshots by adding your OpenAI API key.
            </p>
            <Button
              onClick={() => onOpenSettings?.()}
              className="w-full bg-gray-800 hover:bg-gray-900 dark:bg-gray-700 dark:hover:bg-gray-600 text-white py-5 text-base font-medium"
            >
              Add API Key
            </Button>
          </div>
          <div className="bg-gray-50 dark:bg-zinc-800/50 px-6 py-4 border-t border-gray-200 dark:border-zinc-800 select-none">
            <p className="text-xs text-gray-700 dark:text-gray-300">
              You can still upload and organize screenshots without an API key.
            </p>
          </div>
        </>
      )}
    </motion.div>
  );
};

export default EmptyStateCard;
