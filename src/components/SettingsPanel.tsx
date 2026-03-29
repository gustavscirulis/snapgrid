import React, { useState, useEffect, useRef, useCallback } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { useTheme } from "@/components/ThemeProvider";
import { Moon, Sun, SunMoon, Code, X, Check, Plus, Trash2, Download } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { setOpenAIApiKey, setAnthropicApiKey, setGeminiApiKey, setOpenRouterApiKey, hasApiKey, deleteApiKey } from "@/services/aiAnalysisService";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectSeparator, SelectTrigger, SelectValue } from "@/components/ui/select";
import { getAnalyticsConsent, setAnalyticsConsent } from "@/services/analyticsService";
import {
  fetchVisionModels, fetchClaudeModels, fetchGeminiModels, fetchOpenRouterModels,
  getSelectedModel, setSelectedModel,
  getSelectedClaudeModel, setSelectedClaudeModel,
  getSelectedGeminiModel, setSelectedGeminiModel,
  getSelectedOpenRouterModel, setSelectedOpenRouterModel,
  getActiveProvider, setActiveProvider,
  clearModelCache, AUTO_MODEL_VALUE,
  type AIProvider,
} from "@/services/modelService";
import { toast } from "sonner";
import { toast as radixToast } from "@/hooks/use-toast";
import { fetchReleaseNotes, buildWhatsNewDescription } from "@/components/UpdateNotification";
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
  onUpdateSpaceGuidance: (id: string, customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onUpdateAllSpaceGuidance: (customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onReorderSpaces?: (fromIndex: number, toIndex: number) => void;
  onShuffleImages?: () => void;
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
  onUpdateSpaceGuidance,
  onUpdateAllSpaceGuidance,
  onReorderSpaces,
  onShuffleImages,
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
      <DialogContent className="sm:max-w-[600px] rounded-xl border border-gray-200 dark:border-zinc-800/50 bg-white dark:bg-zinc-900 backdrop-blur-none z-[200] focus:outline-none focus:ring-0 p-0 overflow-hidden" style={{ boxShadow: '0 25px 80px -12px rgba(0, 0, 0, 0.4), 0 12px 30px -8px rgba(0, 0, 0, 0.3)' }}>
        {/* Header */}
        <DialogHeader className="border-b border-gray-200 dark:border-zinc-800/50 pb-4 pt-4 px-6">
          <DialogTitle className="text-xl font-semibold text-gray-900 dark:text-gray-100 flex items-center h-8 select-none">Settings</DialogTitle>
          <DialogClose className="h-8 w-8 rounded-md text-gray-500 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-100 hover:bg-gray-100 dark:hover:bg-zinc-800 inline-flex items-center justify-center non-draggable transition-colors focus:outline-none focus:ring-0">
            <X className="h-5 w-5" />
            <span className="sr-only">Close</span>
          </DialogClose>
        </DialogHeader>

        {/* Sidebar + Content */}
        <div className="flex h-[500px]">
          {/* Left nav */}
          <nav className="w-[140px] flex-shrink-0 border-r border-gray-200 dark:border-zinc-800/50 p-2 space-y-0.5">
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
            <AnimatePresence mode="wait" initial={false}>
              {activeTab === "general" && (
                <motion.div
                  key="general"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.15 }}
                >
                  <ThemeSelector />

                  <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/50 space-y-4">
                    <h3 className="text-[11px] font-medium uppercase tracking-wide text-gray-400 dark:text-gray-500 select-none">AI Analysis</h3>
                    <ProviderSelector provider={activeProvider} onProviderChange={handleProviderChange} />
                    <ApiKeySection isOpen={open} provider={activeProvider} onKeyChange={handleKeyChange} />
                    <ModelSelector isOpen={open} provider={activeProvider} keyVersion={keyVersion} />
                  </div>

                  <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/50">
                    <QueueSection />
                  </div>

                  <div className="mt-6 pt-6 border-t border-gray-100 dark:border-zinc-800/50">
                    <AnalyticsSection />
                  </div>
                </motion.div>
              )}

              {activeTab === "spaces" && (
                <motion.div
                  key="spaces"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.15 }}
                >
                  <SpacesTab
                    spaces={spaces}
                    activeSpaceId={activeSpaceId}
                    allSpacePromptConfig={allSpacePromptConfig}
                    onCreateSpace={onCreateSpace}
                    onRenameSpace={onRenameSpace}
                    onDeleteSpace={onDeleteSpace}
                    onUpdateSpaceGuidance={onUpdateSpaceGuidance}
                    onUpdateAllSpaceGuidance={onUpdateAllSpaceGuidance}
                    onReorderSpaces={onReorderSpaces}
                  />
                </motion.div>
              )}

              {activeTab === "developer" && (
                <motion.div
                  key="developer"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.15 }}
                >
                  <DeveloperSection onShuffleImages={onShuffleImages} />
                </motion.div>
              )}
            </AnimatePresence>
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

const PROVIDER_LABELS: Record<AIProvider, string> = {
  openai: "OpenAI",
  anthropic: "Claude",
  gemini: "Gemini",
  openrouter: "OpenRouter",
};

const ProviderSelector = ({ provider, onProviderChange }: { provider: AIProvider; onProviderChange: (p: AIProvider) => void }) => {
  return (
    <div className="flex items-center justify-between">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Provider</span>
      <Select value={provider} onValueChange={(v) => onProviderChange(v as AIProvider)}>
        <SelectTrigger className="w-[160px] h-8 rounded-md text-sm border-gray-200 dark:border-zinc-700/50 bg-gray-50 dark:bg-zinc-800 focus:outline-none focus:ring-0 focus:border-gray-300 dark:focus:border-zinc-600">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {(Object.keys(PROVIDER_LABELS) as AIProvider[]).map((key) => (
            <SelectItem key={key} value={key}>
              {PROVIDER_LABELS[key]}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
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
  openrouter: {
    linkText: "Get an API key",
    url: "https://openrouter.ai/settings/keys",
    prefix: "sk-or-",
    placeholder: "sk-or-...",
    setKey: setOpenRouterApiKey,
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
      const providerNames: Record<AIProvider, string> = { openai: "OpenAI", anthropic: "Anthropic", gemini: "Google AI Studio", openrouter: "OpenRouter" };
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
            className="h-9 rounded-md text-sm border-gray-200 dark:border-zinc-700/50 bg-gray-50 dark:bg-zinc-800 focus:outline-none focus:ring-0 focus:border-gray-300 dark:focus:border-zinc-600 transition-colors"
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
        <div className="flex items-center justify-between h-9 rounded-md border border-gray-200 dark:border-zinc-700/50 bg-gray-50 dark:bg-zinc-800 px-3">
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
  const [models, setModels] = useState<Array<{ id: string; display_name?: string }>>([]);
  const [selectedModelValue, setSelectedModelValue] = useState<string>(AUTO_MODEL_VALUE);
  const [isLoading, setIsLoading] = useState(false);
  const [keyExists, setKeyExists] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    let stale = false;

    const load = async () => {
      const exists = await hasApiKey(provider);
      if (stale) return;
      setKeyExists(exists);
      if (!exists) {
        setModels([]);
        return;
      }

      setIsLoading(true);
      setError(null);
      setModels([]);
      try {
        if (provider === 'gemini') {
          const [pref, modelList] = await Promise.all([
            getSelectedGeminiModel(),
            fetchGeminiModels(),
          ]);
          if (stale) return;
          setSelectedModelValue(pref);
          setModels(modelList);
        } else if (provider === 'anthropic') {
          const [pref, modelList] = await Promise.all([
            getSelectedClaudeModel(),
            fetchClaudeModels(),
          ]);
          if (stale) return;
          setSelectedModelValue(pref);
          setModels(modelList);
        } else if (provider === 'openrouter') {
          const [pref, modelList] = await Promise.all([
            getSelectedOpenRouterModel(),
            fetchOpenRouterModels(),
          ]);
          if (stale) return;
          setSelectedModelValue(pref);
          setModels(modelList);
        } else {
          const [pref, modelList] = await Promise.all([
            getSelectedModel(),
            fetchVisionModels(),
          ]);
          if (stale) return;
          setSelectedModelValue(pref);
          setModels(modelList);
        }
      } catch {
        if (!stale) setError("Could not load models");
      } finally {
        if (!stale) setIsLoading(false);
      }
    };

    load();
    return () => { stale = true; };
  }, [isOpen, provider, keyVersion]);

  if (!keyExists) return null;

  const handleModelChange = async (value: string) => {
    setSelectedModelValue(value);
    if (provider === 'gemini') {
      await setSelectedGeminiModel(value);
    } else if (provider === 'anthropic') {
      await setSelectedClaudeModel(value);
    } else if (provider === 'openrouter') {
      await setSelectedOpenRouterModel(value);
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

  const showAutoOption = provider !== 'openrouter';
  const latestModelName = models.length > 0 ? models[0].id : "...";

  return (
    <div className="space-y-2">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Model</span>
      <Select value={selectedModelValue} onValueChange={handleModelChange} disabled={isLoading}>
        <SelectTrigger className="h-9 rounded-md text-sm border-gray-200 dark:border-zinc-700/50 bg-gray-50 dark:bg-zinc-800 focus:outline-none focus:ring-0 focus:border-gray-300 dark:focus:border-zinc-600">
          <SelectValue placeholder={isLoading ? "Loading models..." : "Select model..."} />
        </SelectTrigger>
        <SelectContent side="bottom" sideOffset={4} avoidCollisions={false} className="max-h-52">
          {showAutoOption && (
            <>
              <SelectItem value={AUTO_MODEL_VALUE}>
                Use latest ({latestModelName})
              </SelectItem>
              {models.length > 0 && <SelectSeparator />}
            </>
          )}
          {models.map((m) => (
            <SelectItem key={m.id} value={m.id}>
              {m.display_name || m.id}
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
  const [exported, setExported] = useState(false);
  const isElectron = window?.electron && typeof window.electron !== 'undefined';

  const handleExportShortcut = async () => {
    if (!window.electron?.exportShortcut) return;
    const result = await window.electron.exportShortcut();
    if (result.success) {
      setExported(true);
      toast.success('Shortcut saved to Downloads');
      setTimeout(() => setExported(false), 2000);
    } else {
      toast.error('Failed to export shortcut');
    }
  };

  return (
    <div className="space-y-2">
      <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Mobile Import</span>
      <p className="text-xs text-gray-500 dark:text-gray-500 select-none">
        Images saved to the queue folder are automatically imported into SnapGrid. To send images from your iPhone, install the shortcut below, then share any image and select "Save to SnapGrid".
      </p>
      {isElectron && (
        <motion.div whileTap={{ scale: 0.98 }} transition={{ duration: 0.1 }}>
          <Button
            variant="outline"
            size="sm"
            className={`w-full text-xs h-8 transition-colors duration-200 ${
              exported
                ? "border-green-200 dark:border-green-900 text-green-600 dark:text-green-400 bg-green-50 dark:bg-green-950/30"
                : ""
            }`}
            onClick={handleExportShortcut}
            disabled={exported}
          >
            <AnimatePresence mode="wait" initial={false}>
              {exported ? (
                <motion.span
                  key="done"
                  className="flex items-center"
                  initial={{ opacity: 0, y: 4 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -4 }}
                  transition={{ duration: 0.15 }}
                >
                  <Check className="h-3.5 w-3.5 mr-1.5" />
                  Saved to Downloads
                </motion.span>
              ) : (
                <motion.span
                  key="download"
                  className="flex items-center"
                  initial={{ opacity: 0, y: 4 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -4 }}
                  transition={{ duration: 0.15 }}
                >
                  <Download className="h-3.5 w-3.5 mr-1.5" />
                  Get iOS Shortcut
                </motion.span>
              )}
            </AnimatePresence>
          </Button>
        </motion.div>
      )}
      <code className="block text-[11px] bg-gray-100 dark:bg-zinc-800 px-2.5 py-1.5 rounded-md text-gray-600 dark:text-gray-300 font-mono select-all">
        iCloud Drive/Documents/SnapGrid/queue/
      </code>
    </div>
  );
};

const DeveloperSection = ({ onShuffleImages }: { onShuffleImages?: () => void }) => {
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
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Shuffle grid order</span>
        <Button
          variant="outline"
          size="sm"
          onClick={() => {
            onShuffleImages?.();
            toast.success("Grid order shuffled for this session.");
          }}
          className="h-7 text-xs border-rose-300 dark:border-rose-800 text-rose-600 dark:text-rose-400 hover:bg-rose-100 dark:hover:bg-rose-900/50"
        >
          Shuffle
        </Button>
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

      <div className="flex justify-between items-center gap-4">
        <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Show "What's New" toast</span>
        <Button
          variant="outline"
          size="sm"
          onClick={async () => {
            const version = window.electron?.appVersion || '1.0.0';
            try {
              const items = await fetchReleaseNotes(version);
              radixToast({
                title: `Updated to v${version}`,
                description: buildWhatsNewDescription(version, items),
                duration: 8000,
              });
            } catch {
              toast.error('Failed to fetch release notes from GitHub');
            }
          }}
          className="h-7 text-xs border-rose-300 dark:border-rose-800 text-rose-600 dark:text-rose-400 hover:bg-rose-100 dark:hover:bg-rose-900/50"
        >
          Show
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
  onUpdateSpaceGuidance: (id: string, customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onUpdateAllSpaceGuidance: (customPrompt: string | undefined, useCustomPrompt: boolean) => Promise<void>;
  onReorderSpaces?: (fromIndex: number, toIndex: number) => void;
}

const SpacesTab = ({
  spaces,
  activeSpaceId,
  allSpacePromptConfig,
  onCreateSpace,
  onRenameSpace,
  onDeleteSpace,
  onUpdateSpaceGuidance,
  onUpdateAllSpaceGuidance,
  onReorderSpaces,
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
      onUpdateAllSpaceGuidance(currentPromptText || undefined, checked);
    } else {
      onUpdateSpaceGuidance(selectedSpaceId, currentPromptText || undefined, checked);
    }
  };

  const handlePromptChange = useCallback((text: string) => {
    setLocalPromptText(text);
    // Debounce persistence
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      if (selectedSpaceId === null) {
        onUpdateAllSpaceGuidance(text, true);
      } else {
        onUpdateSpaceGuidance(selectedSpaceId, text, true);
      }
    }, 500);
  }, [selectedSpaceId, onUpdateAllSpaceGuidance, onUpdateSpaceGuidance]);

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

  // Drag reorder state (vertical variant of SpaceTabBar pattern)
  const [reorderDragId, setReorderDragId] = useState<string | null>(null);
  const [dragTranslateY, setDragTranslateY] = useState(0);
  const [dragTargetIndex, setDragTargetIndex] = useState<number | null>(null);
  const dragTargetIndexRef = useRef<number | null>(null);
  const reorderDragRef = useRef<{
    spaceId: string;
    originalIndex: number;
    startY: number;
    isDragging: boolean;
    itemPositions: { top: number; midY: number; height: number }[];
    draggedHeight: number;
    gap: number;
  } | null>(null);
  const itemRefsMap = useRef<Map<string, HTMLElement>>(new Map());

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      const state = reorderDragRef.current;
      if (!state) return;

      if (!state.isDragging) {
        const dy = e.clientY - state.startY;
        if (dy * dy < 25) return;

        state.isDragging = true;
        const positions = spaces.map(s => {
          const el = itemRefsMap.current.get(s.id);
          if (!el) return { top: 0, midY: 0, height: 0 };
          const rect = el.getBoundingClientRect();
          return { top: rect.top, midY: rect.top + rect.height / 2, height: rect.height };
        });
        state.itemPositions = positions;
        state.draggedHeight = positions[state.originalIndex]?.height ?? 0;
        state.gap = positions.length >= 2
          ? Math.abs(positions[1].top - (positions[0].top + positions[0].height))
          : 4;

        setReorderDragId(state.spaceId);
        document.body.style.cursor = 'grabbing';
      }

      setDragTranslateY(e.clientY - state.startY);

      let targetIndex = 0;
      for (let i = 0; i < state.itemPositions.length; i++) {
        if (e.clientY >= state.itemPositions[i].midY) {
          targetIndex = i;
        }
      }
      dragTargetIndexRef.current = targetIndex;
      setDragTargetIndex(targetIndex);
    };

    const handleMouseUp = () => {
      const state = reorderDragRef.current;
      if (!state) return;

      if (state.isDragging && onReorderSpaces) {
        const target = dragTargetIndexRef.current ?? state.originalIndex;
        if (target !== state.originalIndex) {
          onReorderSpaces(state.originalIndex, target);
        }
      }

      reorderDragRef.current = null;
      dragTargetIndexRef.current = null;
      setReorderDragId(null);
      setDragTranslateY(0);
      setDragTargetIndex(null);
      document.body.style.cursor = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [spaces, onReorderSpaces]);

  const handleItemMouseDown = useCallback((e: React.MouseEvent, spaceId: string, spaceIndex: number) => {
    if (e.button !== 0 || editingNameId) return;
    reorderDragRef.current = {
      spaceId,
      originalIndex: spaceIndex,
      startY: e.clientY,
      isDragging: false,
      itemPositions: [],
      draggedHeight: 0,
      gap: 4,
    };
  }, [editingNameId]);

  const getItemShiftY = useCallback((spaceIndex: number): number => {
    if (dragTargetIndex === null || !reorderDragRef.current) return 0;
    const { originalIndex, draggedHeight, gap } = reorderDragRef.current;
    if (spaceIndex === originalIndex) return 0;

    const shiftAmount = draggedHeight + gap;

    if (originalIndex < dragTargetIndex) {
      if (spaceIndex > originalIndex && spaceIndex <= dragTargetIndex) {
        return -shiftAmount;
      }
    } else if (originalIndex > dragTargetIndex) {
      if (spaceIndex >= dragTargetIndex && spaceIndex < originalIndex) {
        return shiftAmount;
      }
    }
    return 0;
  }, [dragTargetIndex]);

  const isReorderDragging = reorderDragId !== null;

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
        {spaceItems.map((item, itemIndex) => {
          const isSelected = selectedSpaceId === item.id;
          const isEditing = item.id !== null && editingNameId === item.id;
          const spaceIndex = itemIndex - 1; // index within spaces array (-1 for "All")

          const isBeingDragged = reorderDragId === item.id;

          const itemDiv = (
            <div
              ref={item.id !== null ? (el: HTMLDivElement | null) => {
                if (el) itemRefsMap.current.set(item.id!, el);
                else itemRefsMap.current.delete(item.id!);
              } : undefined}
              onClick={() => {
                if (reorderDragRef.current?.isDragging) return;
                if (!isEditing) setSelectedSpaceId(item.id);
              }}
              onMouseDown={item.id !== null ? (e: React.MouseEvent) => handleItemMouseDown(e, item.id!, spaceIndex) : undefined}
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
                    custom guidance
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

          if (item.id !== null) {
            const yOffset = isBeingDragged ? dragTranslateY : getItemShiftY(spaceIndex);
            return (
              <motion.div
                key={item.id}
                animate={{
                  y: yOffset,
                  scale: isBeingDragged ? 1.02 : 1,
                  boxShadow: isBeingDragged
                    ? '0 4px 12px rgba(0,0,0,0.12)'
                    : '0 0px 0px rgba(0,0,0,0)',
                }}
                transition={{
                  y: isBeingDragged
                    ? { duration: 0 }
                    : isReorderDragging
                      ? { type: "spring", damping: 30, stiffness: 400 }
                      : { duration: 0 },
                  scale: { type: "spring", damping: 30, stiffness: 400 },
                  boxShadow: { type: "spring", damping: 30, stiffness: 400 },
                }}
                style={{
                  zIndex: isBeingDragged ? 10 : undefined,
                  position: 'relative',
                }}
              >
                {itemDiv}
              </motion.div>
            );
          }

          return <React.Fragment key="__all__">{itemDiv}</React.Fragment>;
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

      {/* Guidance section */}
      <div className="pt-4 border-t border-gray-100 dark:border-zinc-800/50 space-y-3">
        <h3 className="text-[11px] font-medium uppercase tracking-wide text-gray-400 dark:text-gray-500 select-none">
          Analysis Guidance
          {selectedSpaceId === null ? " — All" : ` — ${selectedSpace?.name ?? ""}`}
        </h3>

        <div className="flex items-center justify-between">
          <span className="text-sm text-gray-700 dark:text-gray-300 select-none">Custom guidance</span>
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
              className="w-full h-32 text-xs rounded-md border border-gray-200 dark:border-zinc-700/50 bg-gray-50 dark:bg-zinc-800 p-3 resize-y focus:outline-none focus:border-gray-300 dark:focus:border-zinc-600 transition-colors text-gray-800 dark:text-gray-200 placeholder:text-gray-400"
              placeholder="e.g., Focus on architectural details and building materials"
            />
          </div>
        ) : (
          <p className="text-xs text-gray-500 dark:text-gray-500 select-none">
            Using default guidance. App updates will automatically improve analysis.
          </p>
        )}
      </div>
    </div>
  );
};
