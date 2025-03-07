import React, { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ApiKeyInput } from "@/components/ApiKeyInput";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon, Key } from "lucide-react";
import { setOpenAIApiKey, hasApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";

interface SettingsPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

const ThemeToggle = () => {
  const { theme, setTheme } = useTheme();

  return (
    <div className="space-y-2">
      <h3 className="text-sm font-medium">Theme</h3>
      <div className="flex gap-2">
        <Button
          variant={theme === "light" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("light")}
          className="flex items-center gap-1"
        >
          <Sun className="h-4 w-4" />
          <span>Light</span>
        </Button>
        <Button
          variant={theme === "dark" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("dark")}
          className="flex items-center gap-1"
        >
          <Moon className="h-4 w-4" />
          <span>Dark</span>
        </Button>
        <Button
          variant={theme === "system" ? "default" : "outline"}
          size="sm"
          onClick={() => setTheme("system")}
          className="flex items-center gap-1"
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
  const [hasKey, setHasKey] = useState(false);
  
  useEffect(() => {
    // Check if API key exists on mount
    setHasKey(hasApiKey());
  }, []);

  const handleUpdateApiKey = () => {
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
      // Save the API key
      setOpenAIApiKey(apiKey.trim());
      
      // Store in localStorage for persistence
      localStorage.setItem("openai-api-key", apiKey.trim());
      
      setHasKey(true);
      toast.success(hasKey ? "API key updated successfully" : "API key added successfully");
      setApiKey("");
    } catch (err) {
      console.error("Error saving API key:", err);
      toast.error("Failed to update API key");
    } finally {
      setIsSubmitting(false);
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
            placeholder={hasKey ? "••••••••••••••••••••" : "sk-..."}
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                handleUpdateApiKey();
              }
            }}
            className={hasKey ? "border-green-500/30 bg-green-500/5" : ""}
          />
          <Button 
            onClick={handleUpdateApiKey}
            disabled={isSubmitting || !apiKey.trim()}
          >
            {isSubmitting ? "Updating..." : hasKey ? "Update" : "Add Key"}
          </Button>
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          {hasKey ? (
            <>
              <Key className="h-3 w-3 text-green-500" />
              <span className="text-green-500">API key is currently set</span>
            </>
          ) : (
            "No API key set"
          )}
        </div>
      </div>
    </div>
  );
};

const SettingsPanel: React.FC<SettingsPanelProps> = ({ open, onOpenChange }) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Settings</DialogTitle>
        </DialogHeader>
        
        <div className="flex flex-col gap-6 py-4">
          <ThemeToggle />
          <ApiKeySection />
        </div>
      </DialogContent>
    </Dialog>
  );
};

export default SettingsPanel;
