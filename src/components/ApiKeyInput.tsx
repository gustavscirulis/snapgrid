import React, { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { 
  Dialog, 
  DialogContent, 
  DialogDescription, 
  DialogFooter, 
  DialogHeader, 
  DialogTitle 
} from "@/components/ui/dialog";
import { Key } from "lucide-react";
import { setOpenAIApiKey, hasApiKey } from "@/services/aiAnalysisService";
import { toast } from "sonner";

interface ApiKeyInputProps {
  inSettingsPanel?: boolean;
}

export function ApiKeyInput({ inSettingsPanel = false }: ApiKeyInputProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [apiKey, setApiKey] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [keyExists, setKeyExists] = useState(false);

  // Check for API key on component mount
  useEffect(() => {
    const checkApiKey = async () => {
      const exists = await hasApiKey();
      setKeyExists(exists);
      
      // If in settings panel, don't open dialog automatically
      if (!exists && !inSettingsPanel) {
        setIsOpen(true);
      }
    };
    
    checkApiKey();
  }, [inSettingsPanel]);

  const handleSubmit = async () => {
    if (!apiKey.trim().startsWith("sk-")) {
      setError("Invalid API key format. OpenAI API keys start with 'sk-'");
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      // Save the API key securely
      const success = await setOpenAIApiKey(apiKey.trim());
      
      if (success) {
        setIsOpen(false);
        setKeyExists(true);
        toast.success("API key saved successfully. New images will now be analyzed with OpenAI Vision.");
      } else {
        throw new Error("Failed to save API key");
      }
    } catch (err) {
      console.error("Error saving API key:", err);
      setError("Failed to save API key");
      toast.error("Failed to save API key");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleOpenChange = (open: boolean) => {
    // Only allow closing if we have a key or user is forcing close
    if (!open && keyExists) {
      setIsOpen(false);
    } else {
      setIsOpen(open);
    }
  };

  if (inSettingsPanel) {
    return (
      <Button 
        variant="outline" 
        size="sm" 
        onClick={() => setIsOpen(true)}
        className="text-xs rounded-md border-gray-300 dark:border-gray-700 bg-white/80 dark:bg-zinc-800/80 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-zinc-700"
      >
        {keyExists ? "Update API Key" : "Set API Key"}
      </Button>
    );
  }

  return (
    <>
      <Button 
        variant="outline" 
        size="sm" 
        onClick={() => setIsOpen(true)}
        className="flex items-center gap-1 text-xs rounded-md border-gray-300 dark:border-gray-700 bg-white/80 dark:bg-zinc-800/80"
      >
        <Key className="h-3.5 w-3.5" />
        <span>{keyExists ? "Update API Key" : "Set API Key"}</span>
      </Button>

      <Dialog open={isOpen} onOpenChange={handleOpenChange}>
        <DialogContent className="sm:max-w-md rounded-xl border-transparent bg-white/95 dark:bg-zinc-900/95 backdrop-blur-xl shadow-xl">
          <DialogHeader className="border-b border-gray-200 dark:border-gray-800 pb-4 mb-4">
            <DialogTitle className="text-xl font-medium">OpenAI API Key</DialogTitle>
            <DialogDescription className="text-gray-500 dark:text-gray-400 mt-1">
              Enter your OpenAI API key to enable AI image analysis
            </DialogDescription>
          </DialogHeader>
          
          <div className="flex flex-col gap-4 py-2 max-h-[calc(100vh-300px)] overflow-y-auto pr-1 mac-scrollbar">
            <Input
              id="apiKey"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              className="rounded-md text-sm border-gray-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 focus:ring-1 focus:ring-gray-500 dark:focus:ring-gray-400"
              type="password"
            />
            {error && (
              <p className="text-sm text-red-500">{error}</p>
            )}
            <p className="text-sm text-gray-500 dark:text-gray-400">
              You'll need an OpenAI API key with access to GPT-4 Vision models. 
              <a 
                href="https://platform.openai.com/api-keys" 
                target="_blank" 
                rel="noreferrer" 
                className="underline text-gray-700 dark:text-gray-300 ml-1"
              >
                Get an API key
              </a>
            </p>
            <div className="text-sm bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 text-amber-800 dark:text-amber-200 p-3 rounded-md">
              <strong>Note:</strong> Image analysis requires the gpt-4o model access. Make sure your API key has access to the latest GPT-4o model.
            </div>
          </div>

          <DialogFooter className="mt-6 border-t border-gray-200 dark:border-zinc-800 pt-4">
            <Button
              variant="secondary"
              onClick={() => {
                if (keyExists) {
                  setIsOpen(false);
                }
              }}
              className="text-gray-700 dark:text-gray-300"
            >
              Cancel
            </Button>
            <Button
              onClick={handleSubmit}
              disabled={isSubmitting || !apiKey.trim()}
              className="bg-gray-900 dark:bg-white hover:bg-gray-800 dark:hover:bg-gray-100 text-white dark:text-gray-900"
            >
              {isSubmitting ? "Saving..." : "Save Key"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
