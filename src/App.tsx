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
        // Check if TelemetryDeck endpoint is reachable
        try {
          await fetch('https://nom.telemetrydeck.com/healthz', { 
            method: 'GET',
            mode: 'no-cors' 
          });
        } catch (connectError) {
          // Silently fail
        }
        
        // First initialize
        await initializeAnalytics();
        
        // Send test signals with timeout to ensure they fire after initialization
        setTimeout(async () => {
          try {
            await sendAnalyticsEvent('app-loaded', { 
              timestamp: new Date().toISOString(),
              isElectron
            });
          } catch (signalError) {
            // Silently fail
          }
        }, 2000);
        
        // Try with different intervals in case there's a timing issue
        setTimeout(async () => {
          try {
            await sendAnalyticsEvent('app-ready', { 
              timestamp: new Date().toISOString(),
              isElectron
            });
          } catch (signalError) {
            // Silently fail
          }
        }, 5000);
        
      } catch (error) {
        // Analytics initialization failed, but we don't want to break the app
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
