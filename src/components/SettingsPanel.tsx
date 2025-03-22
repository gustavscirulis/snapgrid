import React, { useState, useEffect } from "react";
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
      <DialogContent className="sm:max-w-[450px] rounded-xl border-transparent bg-white/90 dark:bg-zinc-900/90 backdrop-blur-xl shadow-xl">
        <DialogHeader className="border-b border-gray-200 dark:border-zinc-800 pb-4 mb-4">
          <DialogTitle className="text-xl font-medium leading-6 flex items-center h-8">Settings</DialogTitle>
        </DialogHeader>
        <div className="py-1 space-y-6 max-h-[calc(100vh-200px)] overflow-y-auto pr-1 mac-scrollbar">
          <ThemeSelector />
          <div className="h-px bg-gray-200 dark:bg-zinc-800 my-8" aria-hidden="true" />
          <ApiKeySection />
        </div>
      </DialogContent>
    </Dialog>
  );
}

const ThemeSelector = () => {
  const { theme, setTheme } = useTheme();

  return (
    <section className="space-y-3">
      <h3 className="text-sm font-semibold text-gray-800 dark:text-gray-200">Appearance</h3>
      <div className="flex w-full h-8 p-0.5 bg-gray-100 dark:bg-zinc-800 rounded-md overflow-hidden shadow-inner">
        <button
          onClick={() => setTheme("light")}
          className={`flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "light" 
            ? "bg-gray-300 dark:bg-gray-600 shadow-sm" 
            : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
          }`}
        >
          <Sun className="h-3.5 w-3.5 mr-1.5" />
          Light
        </button>
        <button
          onClick={() => setTheme("dark")}
          className={`flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "dark" 
            ? "bg-gray-400 dark:bg-gray-600 text-white shadow-sm" 
            : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
          }`}
        >
          <Moon className="h-3.5 w-3.5 mr-1.5" />
          Dark
        </button>
        <button
          onClick={() => setTheme("system")}
          className={`flex items-center justify-center flex-1 text-xs font-medium rounded-md transition-all focus:outline-none ${
            theme === "system" 
            ? "bg-gray-400 dark:bg-gray-600 text-white shadow-sm" 
            : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300"
          }`}
        >
          <SunMoon className="h-3.5 w-3.5 mr-1.5" />
          Auto
        </button>
      </div>
    </section>
  );
};

const ApiKeySection = () => {
  const [apiKey, setApiKey] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [keyExists, setKeyExists] = useState(false);

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
      <h3 className="text-sm font-semibold text-gray-800 dark:text-gray-200">OpenAI API Key</h3>
      <div className="space-y-4">
        <p className="text-xs text-gray-500 dark:text-gray-400">
          Required for image analysis
        </p>
        {!keyExists ? (
          <div className="flex gap-2 p-0.5">
            <Input
              type="password"
              placeholder="sk-..."
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  handleUpdateApiKey();
                }
              }}
              className="rounded-md text-sm border-gray-300 dark:border-zinc-700 bg-white dark:bg-zinc-800 focus:outline-none focus:ring-0 focus:border-gray-400 dark:focus:border-zinc-600"
            />
            <Button 
              onClick={handleUpdateApiKey}
              disabled={isSubmitting || !apiKey.trim()}
              className="rounded-md bg-gray-600 dark:bg-gray-500 hover:bg-gray-700 dark:hover:bg-gray-600 text-white border-0 text-xs focus:outline-none focus:ring-0"
            >
              {isSubmitting ? "Updating..." : "Update"}
            </Button>
          </div>
        ) : (
          <div className="flex items-center justify-between bg-gray-50 dark:bg-zinc-800/50 p-3 rounded-lg border border-gray-200 dark:border-zinc-800">
            <p className="text-xs text-gray-500 dark:text-gray-400">
              API key is currently set
            </p>
            <Button 
              variant="outline" 
              size="sm"
              onClick={handleDeleteApiKey}
              className="text-xs rounded-md border-gray-300 dark:border-zinc-700 bg-white/80 dark:bg-zinc-800/80 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-zinc-700 focus:outline-none focus:ring-0"
            >
              Remove Key
            </Button>
          </div>
        )}
      </div>
    </section>
  );
};
