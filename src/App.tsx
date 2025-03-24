import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { HashRouter, Routes, Route } from "react-router-dom";
import { ThemeProvider } from "@/components/ThemeProvider";
import { useEffect } from "react";
import { initializeAnalytics, sendAnalyticsEvent } from "@/services/analyticsService";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

// Use HashRouter for Electron compatibility
const App = () => {
  const isElectron = window && typeof window.electron !== 'undefined';
  
  // Initialize analytics on app startup
  useEffect(() => {
    const setupAnalytics = async () => {
      try {
        await initializeAnalytics();
        
        // Single app-ready event after initialization
        setTimeout(() => {
          sendAnalyticsEvent('app-ready', { 
            floatValue: Date.now() / 1000,
            isElectron: isElectron ? 'true' : 'false'
          });
        }, 2000);
      } catch (error) {
        // Silent error in production
      }
    };
    
    setupAnalytics();
  }, [isElectron]);
  
  return (
    <ThemeProvider defaultTheme="system" storageKey="ui-theme">
      <QueryClientProvider client={queryClient}>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          {/* Use HashRouter for better Electron compatibility */}
          <HashRouter>
            <Routes>
              <Route path="/" element={<Index />} />
              {/* ADD ALL CUSTOM ROUTES ABOVE THE CATCH-ALL "*" ROUTE */}
              <Route path="*" element={<NotFound />} />
            </Routes>
          </HashRouter>
        </TooltipProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
};

export default App;
