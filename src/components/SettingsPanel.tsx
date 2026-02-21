import React, { useState, useEffect, useRef } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon, Code, X, Check } from "lucide-react";
import { setOpenAIApiKey, setAnthropicApiKey, hasApiKey, deleteApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getAnalyticsConsent, setAnalyticsConsent } from "@/services/analyticsService";
import {
  fetchVisionModels, fetchClaudeModels,
  getSelectedModel, setSelectedModel,
  getSelectedClaudeModel, setSelectedClaudeModel,
  getActiveProvider, setActiveProvider,
  clearModelCache, AUTO_MODEL_VALUE,
  type OpenAIModel, type ClaudeModel, type AIProvider,
} from "@/services/modelService";
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
  const [activeProvider, setActiveProviderState] = useState<AIProvider>("openai");
  // Bumped when the API key is added or removed, so ModelSelector can react
  const [keyVersion, setKeyVersion] = useState(0);

  // Check for development mode on mount
  useEffect(() => {
    setIsDevMode(isDevelopmentMode());
  }, []);

  // Load provider preference when dialog opens
  useEffect(() => {
    if (open) {
      getActiveProvider().then(setActiveProviderState);
    }
  }, [open]);

  const handleProviderChange = async (provider: AIProvider) => {
    setActiveProviderState(provider);
    await setActiveProvider(provider);
  };

  const handleKeyChange = () => setKeyVersion((v) => v + 1);

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
        <div className="max-h-[calc(100vh-200px)] overflow-y-auto pr-1 mac-scrollbar">
          {/* Appearance — standalone */}
          <ThemeSelector />

          {/* AI settings — tightly grouped */}
          <div className="mt-6 space-y-4">
            <h3 className="text-[11px] font-medium uppercase tracking-wide text-gray-400 dark:text-gray-500 select-none">AI Analysis</h3>
            <ProviderSelector provider={activeProvider} onProviderChange={handleProviderChange} />
            <ApiKeySection isOpen={open} provider={activeProvider} onKeyChange={handleKeyChange} />
            <ModelSelector isOpen={open} provider={activeProvider} keyVersion={keyVersion} />
          </div>

          {/* General — less frequently changed */}
          <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/80 space-y-4">
            <QueueSection />
            <AnalyticsSection />
          </div>

          {isDevMode && (
            <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/80">
              <DeveloperSection />
            </div>
          )}

          <div className="h-1" />
        </div>
      </DialogContent>
    </Dialog>
  );
}

// Shared tab trigger styles
const tabTriggerClass = "flex items-center justify-center gap-1.5 data-[state=active]:bg-white data-[state=active]:dark:bg-zinc-700 data-[state=active]:text-gray-900 dark:data-[state=active]:text-gray-100 data-[state=active]:shadow-sm rounded-sm text-xs";

const ThemeSelector = () => {
  const { theme, setTheme } = useTheme();

  return (
    <div className="flex items-center justify-between">
      <h3 className="text-sm font-medium text-gray-900 dark:text-gray-100 select-none">Appearance</h3>
      <Tabs defaultValue={theme} onValueChange={setTheme}>
        <TabsList className="grid grid-cols-3 h-8 bg-gray-100/80 dark:bg-zinc-800/80 p-0.5 rounded-md">
          <TabsTrigger value="light" className={tabTriggerClass}>
            <Sun className="h-3.5 w-3.5" />
            <span>Light</span>
          </TabsTrigger>
          <TabsTrigger value="dark" className={tabTriggerClass}>
            <Moon className="h-3.5 w-3.5" />
            <span>Dark</span>
          </TabsTrigger>
          <TabsTrigger value="system" className={tabTriggerClass}>
            <SunMoon className="h-3.5 w-3.5" />
            <span>Auto</span>
          </TabsTrigger>
        </TabsList>
      </Tabs>
    </div>
  );
};

const ProviderSelector = ({ provider, onProviderChange }: { provider: AIProvider; onProviderChange: (p: AIProvider) => void }) => {
  return (
    <div className="flex items-center justify-between">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Provider</span>
      <Tabs value={provider} onValueChange={(v) => onProviderChange(v as AIProvider)}>
        <TabsList className="grid grid-cols-2 h-8 bg-gray-100/80 dark:bg-zinc-800/80 p-0.5 rounded-md">
          <TabsTrigger value="openai" className={tabTriggerClass + " px-3"}>
            OpenAI
          </TabsTrigger>
          <TabsTrigger value="anthropic" className={tabTriggerClass + " px-3"}>
            Claude
          </TabsTrigger>
        </TabsList>
      </Tabs>
    </div>
  );
};

const AnalyticsSection = () => {
  const [analyticsEnabled, setAnalyticsEnabled] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

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
    if (window.electron.onAnalyticsConsentChanged) {
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
  }, []);

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
    <div className="flex justify-between items-center gap-4">
      <div className="flex-1">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Anonymous analytics</span>
        <p className="text-xs text-gray-500 dark:text-gray-500 select-none mt-0.5">
          No personal data is collected.
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
  );
};

interface ApiKeySectionProps {
  isOpen: boolean;
  provider: AIProvider;
  onKeyChange: () => void;
}

const PROVIDER_CONFIG = {
  openai: {
    linkText: "Get an API key",
    url: "https://platform.openai.com/api-keys",
    prefix: "sk-",
    placeholder: "sk-...",
    setKey: setOpenAIApiKey,
  },
  anthropic: {
    linkText: "Get an API key",
    url: "https://console.anthropic.com/settings/keys",
    prefix: "sk-ant-",
    placeholder: "sk-ant-...",
    setKey: setAnthropicApiKey,
  },
} as const;

const ApiKeySection = ({ isOpen, provider, onKeyChange }: ApiKeySectionProps) => {
  const [apiKey, setApiKeyValue] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [keyExists, setKeyExists] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const config = PROVIDER_CONFIG[provider];

  // Check if key exists whenever provider or dialog state changes
  useEffect(() => {
    const checkKey = async () => {
      const exists = await hasApiKey(provider);
      setKeyExists(exists);
    };
    checkKey();
  }, [provider, isOpen]);

  // Auto-focus the input field when settings opens and no key exists
  useEffect(() => {
    if (isOpen && !keyExists) {
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen, keyExists]);

  // Handle opening the API key URL in default browser
  const handleOpenApiKeyUrl = (e: React.MouseEvent) => {
    e.preventDefault();
    if (window.electron?.openUrl) {
      window.electron.openUrl(config.url);
    } else {
      window.open(config.url, "_blank", "noopener,noreferrer");
    }
  };

  const handleUpdateApiKey = async () => {
    if (!apiKey.trim()) {
      toast.error("Please enter an API key");
      return;
    }

    if (!apiKey.trim().startsWith(config.prefix)) {
      toast.error(`Invalid API key format. ${provider === 'anthropic' ? 'Anthropic' : 'OpenAI'} API keys start with '${config.prefix}'`);
      return;
    }

    setIsSubmitting(true);
    try {
      const success = await config.setKey(apiKey.trim());

      if (success) {
        toast.success("API key saved");
        setApiKeyValue("");
        setKeyExists(true);
        onKeyChange();
      } else {
        throw new Error("Failed to save API key");
      }
    } catch (err) {
      console.error("Error saving API key:", err);
      toast.error("Failed to save API key");
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDeleteApiKey = async () => {
    if (window.confirm("Are you sure you want to remove your API key?")) {
      try {
        const success = await deleteApiKey(provider);
        if (success) {
          toast.success("API key removed");
          setKeyExists(false);
          onKeyChange();
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
      <div className="flex items-center justify-between">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">API Key</span>
        {!keyExists && (
          <a
            href={config.url}
            onClick={handleOpenApiKeyUrl}
            className="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-500 dark:hover:text-gray-300 underline select-none transition-colors"
          >
            {config.linkText}
          </a>
        )}
      </div>
      {!keyExists ? (
        <div className="flex gap-2">
          <Input
            ref={inputRef}
            type="password"
            placeholder={config.placeholder}
            value={apiKey}
            onChange={(e) => setApiKeyValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                handleUpdateApiKey();
              }
            }}
            className="h-9 rounded-md text-sm border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 focus:outline-none focus:ring-0 focus:border-gray-400 dark:focus:border-zinc-700 transition-colors"
          />
          <Button
            size="default"
            onClick={handleUpdateApiKey}
            disabled={isSubmitting || !apiKey.trim()}
            className="h-9 rounded-md bg-gray-800 hover:bg-gray-900 dark:bg-gray-700 dark:hover:bg-gray-600 text-white border-0 text-xs font-medium select-none transition-colors"
          >
            {isSubmitting ? "Saving..." : "Save"}
          </Button>
        </div>
      ) : (
        <div className="flex items-center justify-between h-9 rounded-md border border-gray-200 dark:border-zinc-800 bg-gray-50 dark:bg-zinc-800/50 px-3">
          <span className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-400 select-none">
            <Check className="h-3.5 w-3.5 text-green-600 dark:text-green-500" />
            Key saved
          </span>
          <button
            onClick={handleDeleteApiKey}
            className="text-xs text-gray-500 hover:text-red-600 dark:text-gray-500 dark:hover:text-red-400 select-none transition-colors"
          >
            Remove
          </button>
        </div>
      )}
    </div>
  );
};

const ModelSelector = ({ isOpen, provider, keyVersion }: { isOpen: boolean; provider: AIProvider; keyVersion: number }) => {
  const [models, setModels] = useState<Array<{ id: string }>>([]);
  const [selectedModelValue, setSelectedModelValue] = useState<string>(AUTO_MODEL_VALUE);
  const [isLoading, setIsLoading] = useState(false);
  const [keyExists, setKeyExists] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;

    const load = async () => {
      const exists = await hasApiKey(provider);
      setKeyExists(exists);
      if (!exists) {
        setModels([]);
        return;
      }

      setIsLoading(true);
      setError(null);
      try {
        if (provider === 'anthropic') {
          const [pref, modelList] = await Promise.all([
            getSelectedClaudeModel(),
            fetchClaudeModels(),
          ]);
          setSelectedModelValue(pref);
          setModels(modelList);
        } else {
          const [pref, modelList] = await Promise.all([
            getSelectedModel(),
            fetchVisionModels(),
          ]);
          setSelectedModelValue(pref);
          setModels(modelList);
        }
      } catch {
        setError("Could not load models");
      } finally {
        setIsLoading(false);
      }
    };

    load();
  }, [isOpen, provider, keyVersion]);

  if (!keyExists) return null;

  const handleModelChange = async (value: string) => {
    setSelectedModelValue(value);
    if (provider === 'anthropic') {
      await setSelectedClaudeModel(value);
    } else {
      await setSelectedModel(value);
    }
    clearModelCache();
    toast.success(
      value === AUTO_MODEL_VALUE
        ? "Using latest model automatically"
        : `Model set to ${value}`
    );
  };

  const latestModelName = models.length > 0 ? models[0].id : "...";

  return (
    <div className="space-y-2">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Model</span>
      <Select value={selectedModelValue} onValueChange={handleModelChange} disabled={isLoading}>
        <SelectTrigger className="h-9 rounded-md text-sm border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 focus:outline-none focus:ring-0 focus:border-gray-400 dark:focus:border-zinc-700">
          <SelectValue placeholder={isLoading ? "Loading models..." : "Select model..."} />
        </SelectTrigger>
        <SelectContent side="bottom" sideOffset={4} avoidCollisions={false} className="max-h-52">
          <SelectItem value={AUTO_MODEL_VALUE}>
            Use latest ({latestModelName})
          </SelectItem>
          {models.length > 0 && <SelectSeparator />}
          {models.map((m) => (
            <SelectItem key={m.id} value={m.id}>
              {m.id}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
      {error && (
        <p className="text-xs text-red-500 dark:text-red-400">{error}</p>
      )}
    </div>
  );
};

const QueueSection = () => {
  return (
    <div className="space-y-2">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Mobile Import</span>
      <p className="text-xs text-gray-500 dark:text-gray-500 select-none">
        Save images from your phone to the queue folder and they'll automatically import.
      </p>
      <code className="block text-[11px] bg-gray-100 dark:bg-zinc-800 px-2.5 py-1.5 rounded-md text-gray-600 dark:text-gray-300 font-mono select-all">
        iCloud Drive/Documents/SnapGrid/queue/
      </code>
    </div>
  );
};

// Developer section component only shown in dev mode
const DeveloperSection = () => {
  const [simulateEmptyState, setSimulateEmptyState] = useState(false);
  const [enablePillClickAnalysis, setEnablePillClickAnalysis] = useState(false);

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
    <section className="space-y-3 p-3 -mx-1 rounded-lg bg-rose-50/80 dark:bg-rose-950/40 border border-rose-200/60 dark:border-rose-900/50">
      <div className="flex items-center gap-1.5">
        <Code className="h-3.5 w-3.5 text-rose-500 dark:text-rose-400" />
        <span className="text-[11px] font-medium uppercase tracking-wide text-rose-500 dark:text-rose-400 select-none">Developer</span>
      </div>

      <div className="flex justify-between items-center gap-4">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Simulate empty state</span>
        <Switch
          id="empty-state-toggle"
          checked={simulateEmptyState}
          onCheckedChange={handleToggleEmptyState}
          className="data-[state=checked]:bg-rose-600 dark:data-[state=checked]:bg-rose-700"
        />
      </div>

      <div className="flex justify-between items-center gap-4">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Pill click analysis</span>
        <Switch
          id="pill-click-analysis-toggle"
          checked={enablePillClickAnalysis}
          onCheckedChange={handleTogglePillClickAnalysis}
          className="data-[state=checked]:bg-rose-600 dark:data-[state=checked]:bg-rose-700"
        />
      </div>

      <div className="flex justify-between items-center gap-4">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Delete all spaces</span>
        <Button
          variant="outline"
          size="sm"
          onClick={async () => {
            if (window.electron?.setUserPreference) {
              await window.electron.setUserPreference('spaces', []);
              toast.success("All spaces deleted. Reload to apply.");
              window.location.reload();
            }
          }}
          className="h-7 text-xs border-rose-300 dark:border-rose-800 text-rose-600 dark:text-rose-400 hover:bg-rose-100 dark:hover:bg-rose-900/50"
        >
          Delete
        </Button>
      </div>
    </section>
  );
};
