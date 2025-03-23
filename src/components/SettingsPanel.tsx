import React, { useState, useEffect, useRef } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ApiKeyInput } from "@/components/ApiKeyInput";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon } from "lucide-react";
import { setOpenAIApiKey, hasApiKey, deleteApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";

interface SettingsPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function SettingsPanel({ open, onOpenChange }: SettingsPanelProps) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[450px] rounded-xl border border-gray-200 dark:border-zinc-800 bg-white/95 dark:bg-zinc-900/95 backdrop-blur-sm shadow-2xl z-[200]">
        <DialogHeader className="border-b border-gray-200 dark:border-zinc-800 pb-4 mb-4">
          <DialogTitle className="text-xl font-semibold text-gray-900 dark:text-gray-100 flex items-center h-8 select-none">Settings</DialogTitle>
        </DialogHeader>
        <div className="py-1 space-y-6 max-h-[calc(100vh-200px)] overflow-y-auto pr-1 mac-scrollbar">
          <ThemeSelector />
          <div className="h-px bg-gray-200 dark:bg-zinc-800 my-8" aria-hidden="true" />
          <ApiKeySection isOpen={open} />
        </div>
      </DialogContent>
    </Dialog>
  );
}

const ThemeSelector = () => {
  const { theme, setTheme } = useTheme();

  return (
    <section className="space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none">Appearance</h3>
      <div className="flex w-full h-8 p-0.5 bg-gray-100 dark:bg-zinc-800 rounded-md overflow-hidden shadow-inner">
        <button
          onClick={() => setTheme("light")}
          className={`select-none flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "light" 
            ? "bg-gray-300 dark:bg-gray-600 shadow-sm text-gray-900 dark:text-gray-100" 
            : "text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100"
          }`}
        >
          <Sun className="h-3.5 w-3.5 mr-1.5" />
          Light
        </button>
        <button
          onClick={() => setTheme("dark")}
          className={`select-none flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "dark" 
            ? "bg-gray-300 dark:bg-gray-600 shadow-sm text-gray-900 dark:text-gray-100" 
            : "text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100"
          }`}
        >
          <Moon className="h-3.5 w-3.5 mr-1.5" />
          Dark
        </button>
        <button
          onClick={() => setTheme("system")}
          className={`select-none flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "system" 
            ? "bg-gray-300 dark:bg-gray-600 shadow-sm text-gray-900 dark:text-gray-100" 
            : "text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-gray-100"
          }`}
        >
          <SunMoon className="h-3.5 w-3.5 mr-1.5" />
          Auto
        </button>
      </div>
    </section>
  );
};

interface ApiKeySectionProps {
  isOpen: boolean;
}

const ApiKeySection = ({ isOpen }: ApiKeySectionProps) => {
  const [apiKey, setApiKey] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [keyExists, setKeyExists] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  
  // Check if running in Electron
  const isElectron = window && 
    typeof window.electron !== 'undefined' && 
    window.electron !== null;

  // Auto-focus the input field when settings opens and no key exists
  useEffect(() => {
    if (isOpen && !keyExists) {
      // Focus after a short delay to ensure the dialog is fully visible
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen, keyExists]);

  // Handle opening the API key URL in default browser
  const handleOpenApiKeyUrl = (e: React.MouseEvent) => {
    e.preventDefault();
    const url = "https://platform.openai.com/api-keys";
    
    if (isElectron && window.electron?.openUrl) {
      // Use Electron's shell to open in default browser
      window.electron.openUrl(url);
    } else {
      // Fallback for non-Electron environments
      window.open(url, "_blank", "noopener,noreferrer");
    }
  };

  // Check for API key when component mounts
  useEffect(() => {
    const checkApiKey = async () => {
      const exists = await hasApiKey();
      setKeyExists(exists);
    };
    
    checkApiKey();
  }, []);

  const handleUpdateApiKey = async () => {
    if (!apiKey.trim()) {
      toast.error("Please enter an API key");
      return;
    }
    
    if (!apiKey.trim().startsWith("sk-")) {
      toast.error("Invalid API key format. OpenAI API keys start with 'sk-'");
      return;
    }

    setIsSubmitting(true);
    try {
      // Save the API key securely
      const success = await setOpenAIApiKey(apiKey.trim());
      
      if (success) {
        toast.success("API key updated successfully");
        setApiKey("");
        setKeyExists(true);
      } else {
        throw new Error("Failed to update API key");
      }
    } catch (err) {
      console.error("Error saving API key:", err);
      toast.error("Failed to update API key");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDeleteApiKey = async () => {
    if (window.confirm("Are you sure you want to remove your API key?")) {
      try {
        const success = await deleteApiKey();
        if (success) {
          toast.success("API key removed");
          setKeyExists(false);
        } else {
          throw new Error("Failed to remove API key");
        }
      } catch (err) {
        console.error("Error removing API key:", err);
        toast.error("Failed to remove API key");
      }
    }
  };

  return (
    <section className="space-y-3">
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none">OpenAI API Key</h3>
      <div className="space-y-4">
        <div className="flex flex-col gap-1">
          <p className="text-sm text-gray-600 dark:text-gray-400 select-none">
            Required for image analysis. <a 
            href="https://platform.openai.com/api-keys" 
            onClick={handleOpenApiKeyUrl}
            className="text-gray-800 hover:text-gray-900 dark:text-gray-300 dark:hover:text-gray-100 underline font-medium select-none"
          >
            Get an OpenAI API key
          </a>.
          </p>
        </div>
        {!keyExists ? (
          <div className="flex gap-2 p-0.5">
            <Input
              ref={inputRef}
              type="password"
              placeholder="sk-..."
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  handleUpdateApiKey();
                }
              }}
              className="rounded-md text-sm border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 focus:outline-none focus:ring-0 focus:border-gray-400 dark:focus:border-zinc-700"
            />
            <Button 
              onClick={handleUpdateApiKey}
              disabled={isSubmitting || !apiKey.trim()}
              className="rounded-md bg-gray-800 hover:bg-gray-900 dark:bg-gray-700 dark:hover:bg-gray-600 text-white border-0 text-xs font-medium select-none"
            >
              {isSubmitting ? "Updating..." : "Update"}
            </Button>
          </div>
        ) : (
          <div className="flex items-center justify-between bg-gray-50 dark:bg-zinc-800/50 p-3 rounded-lg border border-gray-200 dark:border-zinc-800">
            <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
              API key is currently set
            </p>
            <Button 
              variant="outline" 
              size="sm"
              onClick={handleDeleteApiKey}
              className="text-xs rounded-md border-gray-200 dark:border-zinc-800 bg-white/90 dark:bg-zinc-900/90 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-zinc-800 font-medium select-none"
            >
              Remove Key
            </Button>
          </div>
        )}
      </div>
    </section>
  );
};
