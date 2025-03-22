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
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>
        <div className="py-4 space-y-6">
          <ThemeSelector />
          <ApiKeySection />
        </div>
      </DialogContent>
    </Dialog>
  );
}

const ThemeSelector = () => {
  const { theme, setTheme } = useTheme();

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-medium">Theme</h3>
      <div className="flex gap-2">
        <Button
          variant={theme === "light" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("light")}
          className="gap-1"
        >
          <Sun className="h-4 w-4" />
          <span>Light</span>
        </Button>
        <Button
          variant={theme === "dark" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("dark")}
          className="gap-1"
        >
          <Moon className="h-4 w-4" />
          <span>Dark</span>
        </Button>
        <Button
          variant={theme === "system" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("system")}
          className="gap-1"
        >
          <SunMoon className="h-4 w-4" />
          <span>System</span>
        </Button>
      </div>
    </div>
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
    <div className="space-y-2">
      <h3 className="text-sm font-medium">OpenAI API Key</h3>
      <div className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Required for image analysis
        </p>
        <div className="flex gap-2">
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
          />
          <Button 
            onClick={handleUpdateApiKey}
            disabled={isSubmitting || !apiKey.trim()}
          >
            {isSubmitting ? "Updating..." : "Update"}
          </Button>
        </div>
        <div className="flex items-center justify-between">
          <p className="text-xs text-muted-foreground">
            {keyExists ? "API key is currently set" : "No API key set"}
          </p>
          {keyExists && (
            <Button 
              variant="outline" 
              size="sm"
              onClick={handleDeleteApiKey}
            >
              Remove Key
            </Button>
          )}
        </div>
      </div>
    </div>
  );
};
