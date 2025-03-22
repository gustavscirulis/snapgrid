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
        className="flex items-center gap-1"
      >
        <Key className="h-4 w-4" />
        <span>{keyExists ? "Update API Key" : "Set API Key"}</span>
      </Button>

      <Dialog open={isOpen} onOpenChange={handleOpenChange}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>OpenAI API Key</DialogTitle>
            <DialogDescription>
              Enter your OpenAI API key to enable AI image analysis. Your key is stored securely on your device and is never sent to our servers.
            </DialogDescription>
          </DialogHeader>
          
          <div className="flex flex-col gap-4 py-4">
            <Input
              id="apiKey"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              className="w-full"
              type="password"
            />
            {error && (
              <p className="text-sm text-red-500">{error}</p>
            )}
            <p className="text-sm text-muted-foreground">
              You'll need an OpenAI API key with access to GPT-4 Vision models. 
              <a 
                href="https://platform.openai.com/api-keys" 
                target="_blank" 
                rel="noreferrer" 
                className="underline text-primary ml-1"
              >
                Get an API key
              </a>
            </p>
            <div className="text-sm bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-800 text-amber-800 dark:text-amber-200 p-3 rounded-md">
              <strong>Note:</strong> Image analysis requires the gpt-4o model access. Make sure your API key has access to the latest GPT-4o model.
            </div>
          </div>

          <DialogFooter className="flex gap-2 sm:gap-0">
            <Button
              type="button"
              variant="secondary"
              onClick={() => {
                if (keyExists) {
                  setIsOpen(false);
                } else {
                  toast.warning("API key is required for image analysis");
                }
              }}
            >
              Cancel
            </Button>
            <Button 
              type="submit" 
              onClick={handleSubmit}
              disabled={isSubmitting || !apiKey.trim()}
            >
              {isSubmitting ? "Saving..." : "Save API Key"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
