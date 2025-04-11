import React, { useState, useEffect, useRef } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { ApiKeyInput } from "@/components/ApiKeyInput";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon, Code, X } from "lucide-react";
import { setOpenAIApiKey, hasApiKey, deleteApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { getAnalyticsConsent, setAnalyticsConsent } from "@/services/analyticsService";
import { toast } from "sonner";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";

// Helper to detect development mode
const isDevelopmentMode = () => {
  // Check for common development indicators
  if (window.location.hostname === 'localhost' || 
      window.location.hostname === '127.0.0.1' ||
      window.location.port === '8080' || 
      window.location.port === '3000') {
    return true;
  }
  
  // In Electron, check if we have dev tools available
  if (window && typeof window.electron !== 'undefined' && 
      window.electron !== null && 
      (window as any).__REACT_DEVTOOLS_GLOBAL_HOOK__) {
    return true;
  }
  
  // Default to production mode
  return false;
};

interface SettingsPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function SettingsPanel({ open, onOpenChange }: SettingsPanelProps) {
  const [isDevMode, setIsDevMode] = useState(false);
  
  // Check for development mode on mount
  useEffect(() => {
    setIsDevMode(isDevelopmentMode());
  }, []);
  
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[450px] rounded-xl border border-gray-200 dark:border-zinc-800 bg-white dark:bg-black backdrop-blur-none shadow-2xl z-[200] focus:outline-none focus:ring-0 pt-4">
        <DialogHeader className="border-b border-gray-200 dark:border-zinc-800 pb-4 mb-4 -mx-6 px-6">
          <DialogTitle className="text-xl font-semibold text-gray-900 dark:text-gray-100 flex items-center h-8 select-none">Settings</DialogTitle>
          <DialogClose className="h-8 w-8 rounded-md text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-zinc-800 inline-flex items-center justify-center non-draggable transition-colors focus:outline-none focus:ring-0">
            <X className="h-5 w-5" />
            <span className="sr-only">Close</span>
          </DialogClose>
        </DialogHeader>
        <div className="py-1 space-y-8 max-h-[calc(100vh-200px)] overflow-y-auto pr-1 mac-scrollbar">
          <ThemeSelector />
          <ApiKeySection isOpen={open} />
          <AnalyticsSection />
          {isDevMode && <DeveloperSection />}
        </div>
      </DialogContent>
    </Dialog>
  );
}

const ThemeSelector = () => {
  const { theme, setTheme } = useTheme();

  return (
    <section className="space-y-3">
      <div className="space-y-1">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none">Appearance</h3>
      </div>
      <Tabs defaultValue={theme} onValueChange={setTheme} className="w-full">
        <TabsList className="w-full grid grid-cols-3 h-9 bg-gray-100/80 dark:bg-zinc-800/80 p-1 rounded-md">
          <TabsTrigger 
            value="light" 
            className="flex items-center justify-center gap-1.5 data-[state=active]:bg-white data-[state=active]:dark:bg-zinc-700 data-[state=active]:text-gray-900 dark:data-[state=active]:text-gray-100 data-[state=active]:shadow-sm rounded-sm text-xs"
          >
            <Sun className="h-3.5 w-3.5" />
            <span>Light</span>
          </TabsTrigger>
          <TabsTrigger 
            value="dark" 
            className="flex items-center justify-center gap-1.5 data-[state=active]:bg-white data-[state=active]:dark:bg-zinc-700 data-[state=active]:text-gray-900 dark:data-[state=active]:text-gray-100 data-[state=active]:shadow-sm rounded-sm text-xs"
          >
            <Moon className="h-3.5 w-3.5" />
            <span>Dark</span>
          </TabsTrigger>
          <TabsTrigger 
            value="system" 
            className="flex items-center justify-center gap-1.5 data-[state=active]:bg-white data-[state=active]:dark:bg-zinc-700 data-[state=active]:text-gray-900 dark:data-[state=active]:text-gray-100 data-[state=active]:shadow-sm rounded-sm text-xs"
          >
            <SunMoon className="h-3.5 w-3.5" />
            <span>Auto</span>
          </TabsTrigger>
        </TabsList>
      </Tabs>
    </section>
  );
};

const AnalyticsSection = () => {
  const [analyticsEnabled, setAnalyticsEnabled] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const isElectron = window && typeof window.electron !== 'undefined' && window.electron !== null;

  // Load the current analytics consent status
  useEffect(() => {
    const checkAnalyticsConsent = async () => {
      try {
        setIsLoading(true);
        const consent = await getAnalyticsConsent();
        setAnalyticsEnabled(consent);
      } catch (error) {
        // Silent error
      } finally {
        setIsLoading(false);
      }
    };

    checkAnalyticsConsent();
    
    // Set up a listener for consent changes from the main process
    if (isElectron && window.electron.onAnalyticsConsentChanged) {
      const removeListener = window.electron.onAnalyticsConsentChanged((consent: boolean) => {
        console.log('Received analytics consent change event:', consent);
        setAnalyticsEnabled(consent);
        // Only show toast if we're not actively toggling (already handled in handleToggleChange)
        if (!isLoading) {
          toast.success(consent ? "Analytics enabled" : "Analytics disabled");
        }
      });
      
      return () => {
        // Clean up the listener when component unmounts
        if (removeListener) removeListener();
      };
    }
  }, [isElectron]);

  // Handle toggle changes
  const handleToggleChange = async (checked: boolean) => {
    try {
      setIsLoading(true);
      const success = await setAnalyticsConsent(checked);
      if (success) {
        setAnalyticsEnabled(checked);
        toast.success(checked ? "Analytics enabled" : "Analytics disabled");
      }
    } catch (error) {
      toast.error("Failed to update analytics settings");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <section className="space-y-3">
      <div className="flex justify-between items-center gap-4">
        <div className="space-y-1 flex-1">
          <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none">Send anonymous usage data</h3>
          <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
            Helps us understand usage. No personal data is collected.
          </p>
        </div>
        <Switch
          id="analytics-toggle"
          checked={analyticsEnabled}
          onCheckedChange={handleToggleChange}
          disabled={isLoading}
          className="data-[state=checked]:bg-gray-800 dark:data-[state=checked]:bg-zinc-700 data-[state=checked]:text-gray-100"
        />
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
      <div className="space-y-1">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none">OpenAI API Key</h3>
        <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
          Required for image analysis. <a 
          href="https://platform.openai.com/api-keys" 
          onClick={handleOpenApiKeyUrl}
          className="text-gray-800 hover:text-gray-900 dark:text-gray-300 dark:hover:text-gray-100 underline font-medium select-none"
        >
          Get an OpenAI API key
        </a>.
        </p>
      </div>
      <div className="space-y-4">
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
              className="h-9 rounded-md text-sm border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 focus:outline-none focus:ring-0 focus:border-gray-400 dark:focus:border-zinc-700"
            />
            <Button 
              size="default"
              onClick={handleUpdateApiKey}
              disabled={isSubmitting || !apiKey.trim()}
              className="h-9 rounded-md bg-gray-800 hover:bg-gray-900 dark:bg-gray-700 dark:hover:bg-gray-600 text-white border-0 text-xs font-medium select-none"
            >
              {isSubmitting ? "Updating..." : "Update"}
            </Button>
          </div>
        ) : (
          <div className="flex gap-2 p-0.5">
            <div className="flex-1 rounded-md border border-gray-200 dark:border-zinc-800 bg-gray-50 dark:bg-zinc-800/50 flex items-center h-9 px-3 text-xs text-gray-600 dark:text-gray-400 select-none">
              API key is currently set
            </div>
            <Button 
              variant="outline" 
              size="default"
              onClick={handleDeleteApiKey}
              className="h-9 rounded-md text-xs border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-zinc-800 font-medium select-none"
            >
              Remove
            </Button>
          </div>
        )}
      </div>
    </section>
  );
};

// Developer section component only shown in dev mode
const DeveloperSection = () => {
  const [simulateEmptyState, setSimulateEmptyState] = useState(false);
  const [enablePillClickAnalysis, setEnablePillClickAnalysis] = useState(false);
  const isElectron = window && typeof window.electron !== 'undefined' && window.electron !== null;

  // Function to update the app's global state to simulate empty state
  const handleToggleEmptyState = (checked: boolean) => {
    setSimulateEmptyState(checked);
    // Store the setting in localStorage so it persists across reloads
    localStorage.setItem('dev_simulate_empty_state', checked ? 'true' : 'false');
    
    // Force a refresh to apply the change
    window.location.reload();
  };

  // Function to handle pill click analysis toggle
  const handleTogglePillClickAnalysis = (checked: boolean) => {
    setEnablePillClickAnalysis(checked);
    localStorage.setItem('dev_enable_pill_click_analysis', checked ? 'true' : 'false');
  };

  // Load the simulation setting on mount
  useEffect(() => {
    const savedEmptyState = localStorage.getItem('dev_simulate_empty_state');
    const savedPillClickAnalysis = localStorage.getItem('dev_enable_pill_click_analysis');
    if (savedEmptyState === 'true') {
      setSimulateEmptyState(true);
    }
    if (savedPillClickAnalysis === 'true') {
      setEnablePillClickAnalysis(true);
    }
  }, []);

  return (
    <section className="space-y-4 p-3 rounded-md bg-rose-50 dark:bg-rose-950 border border-rose-200 dark:border-rose-900">
      <div className="space-y-1">
        <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 select-none flex items-center gap-1.5">
          <Code className="h-4 w-4 text-rose-600 dark:text-rose-400" />
          Developer Options
        </h3>
        <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
          These options are only available in development mode.
        </p>
      </div>
      
      <div className="flex justify-between items-center gap-4">
        <div className="space-y-1 flex-1">
          <h4 className="text-xs font-medium text-gray-900 dark:text-gray-100 select-none">Simulate Empty State</h4>
          <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
            Shows the empty state UI even when images are present
          </p>
        </div>
        <Switch
          id="empty-state-toggle"
          checked={simulateEmptyState}
          onCheckedChange={handleToggleEmptyState}
          className="data-[state=checked]:bg-rose-600 dark:data-[state=checked]:bg-rose-700"
        />
      </div>

      <div className="flex justify-between items-center gap-4">
        <div className="space-y-1 flex-1">
          <h4 className="text-xs font-medium text-gray-900 dark:text-gray-100 select-none">Enable Pill Click Analysis</h4>
          <p className="text-xs text-gray-600 dark:text-gray-400 select-none">
            Click on pattern pills to refresh AI analysis
          </p>
        </div>
        <Switch
          id="pill-click-analysis-toggle"
          checked={enablePillClickAnalysis}
          onCheckedChange={handleTogglePillClickAnalysis}
          className="data-[state=checked]:bg-rose-600 dark:data-[state=checked]:bg-rose-700"
        />
      </div>
    </section>
  );
};
