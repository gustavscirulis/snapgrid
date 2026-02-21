import React, { useState, useEffect, useRef, useCallback } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon, Code, X, Check, Plus, Trash2 } from "lucide-react";
import { setOpenAIApiKey, setAnthropicApiKey, setGeminiApiKey, hasApiKey, deleteApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getAnalyticsConsent, setAnalyticsConsent } from "@/services/analyticsService";
import {
  fetchVisionModels, fetchClaudeModels, fetchGeminiModels,
  getSelectedModel, setSelectedModel,
  getSelectedClaudeModel, setSelectedClaudeModel,
  getSelectedGeminiModel, setSelectedGeminiModel,
  getActiveProvider, setActiveProvider,
  clearModelCache, AUTO_MODEL_VALUE,
  type AIProvider,
} from "@/services/modelService";
import { toast } from "sonner";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Space, AllSpacePromptConfig } from "@/hooks/useSpaces";

// Helper to detect development mode
const isDevelopmentMode = () => {
  if (window.location.hostname === 'localhost' ||
      window.location.hostname === '127.0.0.1' ||
      window.location.port === '8080' ||
      window.location.port === '3000') {
    return true;
  }
  if (window && typeof window.electron !== 'undefined' &&
      window.electron !== null &&
      (window as any).__REACT_DEVTOOLS_GLOBAL_HOOK__) {
    return true;
  }
  return false;
};

interface SettingsPanelProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  spaces: Space[];
  activeSpaceId: string | null;
  allSpacePromptConfig: AllSpacePromptConfig;
  onCreateSpace: (name: string) => Promise<Space>;
  onRenameSpace: (id: string, name: string) => Promise<void>;
  onDeleteSpace: (id: string) => Promise<void>;
  onUpdateSpacePrompt: (id: string, customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onUpdateAllSpacePrompt: (customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
}

export function SettingsPanel({
  open,
  onOpenChange,
  spaces,
  activeSpaceId,
  allSpacePromptConfig,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
  onUpdateSpacePrompt,
  onUpdateAllSpacePrompt,
}: SettingsPanelProps) {
  const [isDevMode, setIsDevMode] = useState(false);
  const [activeProvider, setActiveProviderState] = useState<AIProvider>("openai");
  const [keyVersion, setKeyVersion] = useState(0);
  const [activeTab, setActiveTab] = useState<"general" | "spaces" | "developer">("general");

  useEffect(() => {
    setIsDevMode(isDevelopmentMode());
  }, []);

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

  const navItems: { id: "general" | "spaces" | "developer"; label: string }[] = [
    { id: "general", label: "General" },
    { id: "spaces", label: "Spaces" },
    ...(isDevMode ? [{ id: "developer" as const, label: "Developer" }] : []),
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[600px] rounded-xl border border-gray-200 dark:border-zinc-800 bg-white dark:bg-black backdrop-blur-none shadow-2xl z-[200] focus:outline-none focus:ring-0 p-0 overflow-hidden">
        {/* Header */}
        <DialogHeader className="border-b border-gray-200 dark:border-zinc-800 pb-4 pt-4 px-6">
          <DialogTitle className="text-xl font-semibold text-gray-900 dark:text-gray-100 flex items-center h-8 select-none">Settings</DialogTitle>
          <DialogClose className="h-8 w-8 rounded-md text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-zinc-800 inline-flex items-center justify-center non-draggable transition-colors focus:outline-none focus:ring-0">
            <X className="h-5 w-5" />
            <span className="sr-only">Close</span>
          </DialogClose>
        </DialogHeader>

        {/* Sidebar + Content */}
        <div className="flex h-[500px]">
          {/* Left nav */}
          <nav className="w-[140px] flex-shrink-0 border-r border-gray-200 dark:border-zinc-800 p-2 space-y-0.5">
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id)}
                className={`w-full text-left px-3 py-1.5 rounded-md text-sm transition-colors select-none ${
                  activeTab === item.id
                    ? "bg-gray-100 dark:bg-zinc-800 text-gray-900 dark:text-gray-100 font-medium"
                    : "text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 hover:bg-gray-50 dark:hover:bg-zinc-800/50"
                }`}
              >
                {item.label}
              </button>
            ))}
          </nav>

          {/* Right content */}
          <div className="flex-1 overflow-y-auto p-6 mac-scrollbar">
            {activeTab === "general" && (
              <>
                <ThemeSelector />

                <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/80 space-y-4">
                  <h3 className="text-[11px] font-medium uppercase tracking-wide text-gray-400 dark:text-gray-500 select-none">AI Analysis</h3>
                  <ProviderSelector provider={activeProvider} onProviderChange={handleProviderChange} />
                  <ApiKeySection isOpen={open} provider={activeProvider} onKeyChange={handleKeyChange} />
                  <ModelSelector isOpen={open} provider={activeProvider} keyVersion={keyVersion} />
                </div>

                <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/80">
                  <QueueSection />
                </div>

                <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/80">
                  <AnalyticsSection />
                </div>
              </>
            )}

            {activeTab === "spaces" && (
              <SpacesTab
                spaces={spaces}
                activeSpaceId={activeSpaceId}
                allSpacePromptConfig={allSpacePromptConfig}
                onCreateSpace={onCreateSpace}
                onRenameSpace={onRenameSpace}
                onDeleteSpace={onDeleteSpace}
                onUpdateSpacePrompt={onUpdateSpacePrompt}
                onUpdateAllSpacePrompt={onUpdateAllSpacePrompt}
              />
            )}

            {activeTab === "developer" && <DeveloperSection />}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ── Shared styles ──────────────────────────────────────────────────

const tabTriggerClass = "flex items-center justify-center gap-1.5 data-[state=active]:bg-white data-[state=active]:dark:bg-zinc-700 data-[state=active]:text-gray-900 dark:data-[state=active]:text-gray-100 data-[state=active]:shadow-sm rounded-sm text-xs";

// ── General tab components ────────────────────────────────────────

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
        <TabsList className="grid grid-cols-3 h-8 bg-gray-100/80 dark:bg-zinc-800/80 p-0.5 rounded-md">
          <TabsTrigger value="openai" className={tabTriggerClass + " px-3"}>
            OpenAI
          </TabsTrigger>
          <TabsTrigger value="anthropic" className={tabTriggerClass + " px-3"}>
            Claude
          </TabsTrigger>
          <TabsTrigger value="gemini" className={tabTriggerClass + " px-3"}>
            Gemini
          </TabsTrigger>
        </TabsList>
      </Tabs>
    </div>
  );
};

const AnalyticsSection = () => {
  const [analyticsEnabled, setAnalyticsEnabled] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

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

    if (window.electron.onAnalyticsConsentChanged) {
      const removeListener = window.electron.onAnalyticsConsentChanged((consent: boolean) => {
        setAnalyticsEnabled(consent);
        if (!isLoading) {
          toast.success(consent ? "Analytics enabled" : "Analytics disabled");
        }
      });

      return () => {
        if (removeListener) removeListener();
      };
    }
  }, []);

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
  gemini: {
    linkText: "Get an API key",
    url: "https://aistudio.google.com/apikey",
    prefix: "AIza",
    placeholder: "AIza...",
    setKey: setGeminiApiKey,
  },
} as const;

const ApiKeySection = ({ isOpen, provider, onKeyChange }: ApiKeySectionProps) => {
  const [apiKey, setApiKeyValue] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [keyExists, setKeyExists] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const config = PROVIDER_CONFIG[provider];

  useEffect(() => {
    const checkKey = async () => {
      const exists = await hasApiKey(provider);
      setKeyExists(exists);
    };
    checkKey();
  }, [provider, isOpen]);

  useEffect(() => {
    if (isOpen && !keyExists) {
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 100);
      return () => clearTimeout(timer);
    }
  }, [isOpen, keyExists]);

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
      const providerNames: Record<AIProvider, string> = { openai: "OpenAI", anthropic: "Anthropic", gemini: "Google AI Studio" };
      toast.error(`Invalid API key format. ${providerNames[provider]} API keys start with '${config.prefix}'`);
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
        if (provider === 'gemini') {
          const [pref, modelList] = await Promise.all([
            getSelectedGeminiModel(),
            fetchGeminiModels(),
          ]);
          setSelectedModelValue(pref);
          setModels(modelList);
        } else if (provider === 'anthropic') {
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
    if (provider === 'gemini') {
      await setSelectedGeminiModel(value);
    } else if (provider === 'anthropic') {
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

const DeveloperSection = () => {
  const [simulateEmptyState, setSimulateEmptyState] = useState(false);
  const [enablePillClickAnalysis, setEnablePillClickAnalysis] = useState(false);

  const handleToggleEmptyState = (checked: boolean) => {
    setSimulateEmptyState(checked);
    localStorage.setItem('dev_simulate_empty_state', checked ? 'true' : 'false');
    window.location.reload();
  };

  const handleTogglePillClickAnalysis = (checked: boolean) => {
    setEnablePillClickAnalysis(checked);
    localStorage.setItem('dev_enable_pill_click_analysis', checked ? 'true' : 'false');
  };

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

      <div className="flex justify-between items-center gap-4">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Reset all custom instructions</span>
        <Button
          variant="outline"
          size="sm"
          onClick={async () => {
            if (window.electron?.setUserPreference) {
              const spacesResult = await window.electron.getUserPreference('spaces', []);
              if (spacesResult.success && Array.isArray(spacesResult.value)) {
                const cleared = spacesResult.value.map((s: Space) => ({
                  ...s,
                  customPrompt: undefined,
                  useCustomPrompt: false,
                }));
                await window.electron.setUserPreference('spaces', cleared);
              }
              await window.electron.setUserPreference('allSpacePrompt', {});
              toast.success("All custom instructions reset. Reload to apply.");
              window.location.reload();
            }
          }}
          className="h-7 text-xs border-rose-300 dark:border-rose-800 text-rose-600 dark:text-rose-400 hover:bg-rose-100 dark:hover:bg-rose-900/50"
        >
          Reset
        </Button>
      </div>
    </section>
  );
};

// ── Spaces tab ────────────────────────────────────────────────────

interface SpacesTabProps {
  spaces: Space[];
  activeSpaceId: string | null;
  allSpacePromptConfig: AllSpacePromptConfig;
  onCreateSpace: (name: string) => Promise<Space>;
  onRenameSpace: (id: string, name: string) => Promise<void>;
  onDeleteSpace: (id: string) => Promise<void>;
  onUpdateSpacePrompt: (id: string, customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onUpdateAllSpacePrompt: (customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
}

const SpacesTab = ({
  spaces,
  activeSpaceId,
  allSpacePromptConfig,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
  onUpdateSpacePrompt,
  onUpdateAllSpacePrompt,
}: SpacesTabProps) => {
  // Which space is selected for editing (null = "All")
  const [selectedSpaceId, setSelectedSpaceId] = useState<string | null>(activeSpaceId);
  const [editingNameId, setEditingNameId] = useState<string | null>(null);
  const [editNameValue, setEditNameValue] = useState("");
  const editNameRef = useRef<HTMLInputElement>(null);

  // Prompt editing state
  const selectedSpace = selectedSpaceId !== null ? spaces.find(s => s.id === selectedSpaceId) : null;
  const isCustom = selectedSpaceId === null
    ? allSpacePromptConfig.useCustomPrompt ?? false
    : selectedSpace?.useCustomPrompt ?? false;
  const currentPromptText = selectedSpaceId === null
    ? allSpacePromptConfig.customPrompt ?? ""
    : selectedSpace?.customPrompt ?? "";

  // Local prompt text for responsive editing
  const [localPromptText, setLocalPromptText] = useState(currentPromptText);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>();

  // Sync local text when selection changes
  useEffect(() => {
    setLocalPromptText(currentPromptText);
  }, [selectedSpaceId, currentPromptText]);

  // Focus name input when editing
  useEffect(() => {
    if (editingNameId) {
      requestAnimationFrame(() => {
        editNameRef.current?.focus();
        editNameRef.current?.select();
      });
    }
  }, [editingNameId]);

  const handleToggleCustomPrompt = (checked: boolean) => {
    if (selectedSpaceId === null) {
      onUpdateAllSpacePrompt(currentPromptText || undefined, checked);
    } else {
      onUpdateSpacePrompt(selectedSpaceId, currentPromptText || undefined, checked);
    }
  };

  const handlePromptChange = useCallback((text: string) => {
    setLocalPromptText(text);
    // Debounce persistence
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      if (selectedSpaceId === null) {
        onUpdateAllSpacePrompt(text, true);
      } else {
        onUpdateSpacePrompt(selectedSpaceId, text, true);
      }
    }, 500);
  }, [selectedSpaceId, onUpdateAllSpacePrompt, onUpdateSpacePrompt]);

  // Clean up debounce on unmount
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  const handleCreateSpace = async () => {
    const space = await onCreateSpace("New Space");
    setSelectedSpaceId(space.id);
    setEditingNameId(space.id);
    setEditNameValue(space.name);
  };

  const commitRename = () => {
    if (editingNameId && editNameValue.trim()) {
      onRenameSpace(editingNameId, editNameValue.trim());
    }
    setEditingNameId(null);
  };

  const handleDeleteSpace = (id: string) => {
    onDeleteSpace(id);
    if (selectedSpaceId === id) {
      setSelectedSpaceId(null);
    }
  };

  // Build the list: "All" + named spaces
  const spaceItems: { id: string | null; name: string; hasCustomPrompt: boolean }[] = [
    { id: null, name: "All", hasCustomPrompt: allSpacePromptConfig.useCustomPrompt ?? false },
    ...spaces.map(s => ({
      id: s.id,
      name: s.name,
      hasCustomPrompt: s.useCustomPrompt ?? false,
    })),
  ];

  return (
    <div className="space-y-4">
      {/* Space list */}
      <div className="space-y-1">
        {spaceItems.map((item) => {
          const isSelected = selectedSpaceId === item.id;
          const isEditing = item.id !== null && editingNameId === item.id;

          return (
            <div
              key={item.id ?? "__all__"}
              onClick={() => {
                if (!isEditing) setSelectedSpaceId(item.id);
              }}
              className={`flex items-center justify-between px-3 py-2 rounded-lg cursor-pointer transition-colors ${
                isSelected
                  ? "bg-gray-100 dark:bg-zinc-800"
                  : "hover:bg-gray-50 dark:hover:bg-zinc-800/50"
              }`}
            >
              <div className="flex items-center gap-2 flex-1 min-w-0">
                {isEditing ? (
                  <input
                    ref={editNameRef}
                    value={editNameValue}
                    onChange={(e) => setEditNameValue(e.target.value)}
                    onBlur={commitRename}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") commitRename();
                      if (e.key === "Escape") setEditingNameId(null);
                    }}
                    className="bg-transparent border-none outline-none text-sm font-medium text-gray-900 dark:text-gray-100 w-full min-w-0"
                  />
                ) : (
                  <span className="text-sm text-gray-900 dark:text-gray-100 truncate select-none">
                    {item.name}
                  </span>
                )}
                {item.hasCustomPrompt && (
                  <span className="flex-shrink-0 text-[10px] px-1.5 py-0.5 rounded bg-gray-200 dark:bg-zinc-700 text-gray-500 dark:text-gray-400 select-none">
                    custom instructions
                  </span>
                )}
              </div>

              {/* Actions for named spaces (not "All") */}
              {item.id !== null && isSelected && !isEditing && (
                <div className="flex items-center gap-1 flex-shrink-0 ml-2">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setEditingNameId(item.id);
                      setEditNameValue(item.name);
                    }}
                    className="text-xs text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 px-1.5 py-0.5 rounded transition-colors"
                  >
                    Rename
                  </button>
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleDeleteSpace(item.id!);
                    }}
                    className="text-gray-400 hover:text-red-500 dark:text-gray-500 dark:hover:text-red-400 p-0.5 rounded transition-colors"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                </div>
              )}
            </div>
          );
        })}

        {/* Add space button */}
        <button
          onClick={handleCreateSpace}
          className="flex items-center gap-2 px-3 py-2 w-full rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-zinc-800/50 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
        >
          <Plus className="h-3.5 w-3.5" />
          <span className="text-sm select-none">Add space</span>
        </button>
      </div>

      {/* Prompt section */}
      <div className="pt-4 border-t border-gray-100 dark:border-zinc-800/80 space-y-3">
        <h3 className="text-[11px] font-medium uppercase tracking-wide text-gray-400 dark:text-gray-500 select-none">
          Analysis Instructions
          {selectedSpaceId === null ? " — All" : ` — ${selectedSpace?.name ?? ""}`}
        </h3>

        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Custom instructions</span>
          <Switch
            checked={isCustom}
            onCheckedChange={handleToggleCustomPrompt}
            className="data-[state=checked]:bg-gray-800 dark:data-[state=checked]:bg-zinc-700 data-[state=checked]:text-gray-100"
          />
        </div>

        {isCustom ? (
          <div className="space-y-2">
            <textarea
              value={localPromptText}
              onChange={(e) => handlePromptChange(e.target.value)}
              className="w-full h-32 text-xs rounded-md border border-gray-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 p-3 resize-y focus:outline-none focus:border-gray-400 dark:focus:border-zinc-700 transition-colors text-gray-800 dark:text-gray-200 placeholder:text-gray-400"
              placeholder="e.g., Focus on architectural details and building materials"
            />
          </div>
        ) : (
          <p className="text-xs text-gray-500 dark:text-gray-500 select-none">
            Using the built-in prompt. App updates will automatically improve analysis.
          </p>
        )}
      </div>
    </div>
  );
};
