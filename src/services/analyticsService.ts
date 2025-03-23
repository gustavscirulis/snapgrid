import TelemetryDeck from '@telemetrydeck/sdk';

// Define the AppID from our configuration
const TELEMETRYDECK_APP_ID = '669E35F6-9D6E-48D0-9D34-B0D044E4A3FA';

// TelemetryDeck instance
let telemetryInstance: any = null;

// Initialize TelemetryDeck with default settings (disabled until explicitly enabled)
let isInitialized = false;

// Check if we're in Electron environment
const isElectron = window && 
  typeof window.electron !== 'undefined' && 
  window.electron !== null;

// Determine if we're in development mode (more robust than relying on process.env)
const isDevelopmentMode = () => {
  // Check for common development indicators
  if (window.location.hostname === 'localhost' || 
      window.location.hostname === '127.0.0.1' ||
      window.location.port === '8080' || 
      window.location.port === '3000') {
    return true;
  }
  
  // In Electron, check if we have dev tools available
  if (isElectron && (window as any).__REACT_DEVTOOLS_GLOBAL_HOOK__) {
    return true;
  }
  
  // Default to production mode
  return false;
};

// Get user consent status from Electron store
export async function getAnalyticsConsent(): Promise<boolean> {
  if (!isElectron) {
    return false;
  }
  
  try {
    const hasConsent = await window.electron.getAnalyticsConsent?.();
    return hasConsent ?? true; // Default to true if undefined
  } catch (error) {
    return false;
  }
}

// Save user consent status
export async function setAnalyticsConsent(consent: boolean): Promise<boolean> {
  if (!isElectron) {
    return false;
  }
  
  try {
    const success = await window.electron.setAnalyticsConsent?.(consent);
    
    // Toggle analytics based on consent
    if (consent) {
      await initializeAnalytics();
    } else {
      disableAnalytics();
    }
    
    return success ?? false;
  } catch (error) {
    return false;
  }
}

// Initialize TelemetryDeck analytics
export async function initializeAnalytics(): Promise<void> {
  // Don't initialize if already initialized
  if (isInitialized) {
    return;
  }
  
  try {
    // Check if user has given consent
    const hasConsent = await getAnalyticsConsent();
    
    if (!hasConsent) {
      return;
    }
    
    // Test mode detection is now more robust
    const isTestMode = isDevelopmentMode();
    
    const clientId = getClientId();
    
    // Get system information
    const systemInfo = getSystemInfo();
    
    // The SDK requires you to create a new instance with the configuration
    try {
      telemetryInstance = new TelemetryDeck({
        appID: TELEMETRYDECK_APP_ID,
        clientUser: clientId,
        testMode: isTestMode,
        // Ensure we're using proper URL
        target: 'https://nom.telemetrydeck.com/v1/collect'
      });
      
      isInitialized = true;
      
      // Send an app start signal
      await telemetryInstance.signal('app-started', systemInfo);
      
      // Add a test signal with a random number to easily identify if it's working
      const randomValue = Math.floor(Math.random() * 1000);
      await telemetryInstance.signal('debug-init', { 
        ...systemInfo,
        timestamp: new Date().toISOString(),
        randomValue: randomValue
      });
      
    } catch (initError) {
      isInitialized = false;
      telemetryInstance = null;
    }
    
  } catch (error) {
    isInitialized = false;
    telemetryInstance = null;
  }
}

// Disable analytics
export function disableAnalytics(): void {
  if (!isInitialized) {
    return;
  }
  
  try {
    // Clear the TelemetryDeck instance
    telemetryInstance = null;
    isInitialized = false;
  } catch (error) {
    // Silently fail
  }
}

// Send a custom analytics event
export async function sendAnalyticsEvent(eventType: string, additionalData: Record<string, any> = {}): Promise<void> {
  if (!isInitialized || !telemetryInstance) {
    return;
  }
  
  try {
    // Add a timestamp to every event for debugging
    const payload = {
      ...getSystemInfo(),
      ...additionalData,
      clientTimestamp: new Date().toISOString()
    };
    
    // Use the proper signal method from the instance
    await telemetryInstance.signal(eventType, payload);
  } catch (error) {
    // Silently fail
  }
}

// Helper to generate a consistent client ID
function getClientId(): string {
  let clientId = localStorage.getItem('telemetrydeck_client_id');
  
  if (!clientId) {
    // Generate a random ID if none exists
    clientId = Math.random().toString(36).substring(2, 15) + 
               Math.random().toString(36).substring(2, 15);
    localStorage.setItem('telemetrydeck_client_id', clientId);
  }
  
  return clientId;
}

// Helper function to get system information
function getSystemInfo(): Record<string, any> {
  const navigator = window.navigator;
  
  // Safely check for process variables
  const electronProcess = (window as any).process || {};
  
  return {
    // Platform information
    platform: navigator.platform,
    userAgent: navigator.userAgent,
    
    // Language settings that may help with geo-targeting
    language: navigator.language,
    languages: navigator.languages ? navigator.languages.join(',') : '',
    
    // Screen information
    screenWidth: window.screen.width,
    screenHeight: window.screen.height,
    
    // Time zone might help with geo approximation
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    
    // App version if available - avoid direct process.env access
    appVersion: isElectron ? (window.electron?.appVersion || 'unknown') : 'unknown',
    
    // Whether this is Electron
    isElectron: isElectron,
    
    // Operating system info if available through Electron
    // Access Electron info more safely
    osInfo: isElectron ? 
      {
        platform: electronProcess.platform || navigator.platform,
        arch: electronProcess.arch || navigator.userAgent,
        // Avoid process.release which may not be available
      } : 
      'web'
  };
} 