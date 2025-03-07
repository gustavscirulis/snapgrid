
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { 
  HashRouter, 
  Routes, 
  Route,
  createHashRouter,
  RouterProvider,
  createRoutesFromElements
} from "react-router-dom";
import { ThemeProvider } from "@/components/ThemeProvider";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient();

// Create router without future flags to avoid compatibility issues
const router = createHashRouter(
  createRoutesFromElements(
    <>
      <Route path="/" element={<Index />} />
      <Route path="*" element={<NotFound />} />
    </>
  )
);

// Use HashRouter for Electron compatibility
const App = () => {
  const isElectron = window && typeof window.electron !== 'undefined';
  
  return (
    <ThemeProvider defaultTheme="system" storageKey="ui-theme">
      <QueryClientProvider client={queryClient}>
        <TooltipProvider>
          <Toaster />
          <Sonner />
          <RouterProvider router={router} />
        </TooltipProvider>
      </QueryClientProvider>
    </ThemeProvider>
  );
};

export default App;
