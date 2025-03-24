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
    if (!window.electron?.getAnalyticsConsent) {
      return false;
    }
    
    const hasConsent = await window.electron.getAnalyticsConsent();
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
    if (!window.electron?.setAnalyticsConsent) {
      return false;
    }
    
    const success = await window.electron.setAnalyticsConsent(consent);
    
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

// Check TelemetryDeck connectivity
async function checkTelemetryDeckConnectivity(): Promise<boolean> {
  try {
    await fetch('https://nom.telemetrydeck.com/v1/collect', {
      method: 'HEAD',
      mode: 'no-cors'
    });
    return true;
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
    
    // Check connectivity silently
    await checkTelemetryDeckConnectivity();
    
    // Test mode detection
    const isTestMode = isDevelopmentMode();
    const clientId = getClientId();
    
    try {
      // Initialize the TelemetryDeck SDK
      telemetryInstance = new TelemetryDeck({
        appID: TELEMETRYDECK_APP_ID,
        clientUser: clientId,
        testMode: isTestMode
      });
      
      isInitialized = true;
      
      // Send initial app-started signal
      setTimeout(async () => {
        try {
          if (telemetryInstance) {
            await telemetryInstance.signal('app-started');
          }
        } catch (error) {
          // Silent error in production
        }
      }, 1000);
      
    } catch (error) {
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
    // Silent error
  }
}

// Send a custom analytics event
export async function sendAnalyticsEvent(eventType: string, additionalData: Record<string, any> = {}): Promise<void> {
  if (!isInitialized || !telemetryInstance) {
    return;
  }
  
  try {
    // Create a simple payload that matches the TelemetryDeck expected format
    const payload: Record<string, any> = {};
    
    // Add system and app information
    payload.appVersion = isElectron ? (window.electron?.appVersion || 'unknown') : 'unknown';
    payload.platform = navigator.platform;
    payload.isElectron = isElectron ? 'true' : 'false';
    
    // Add localization data
    payload.language = navigator.language;
    payload.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    
    // Add key info from additionalData (limited to maintain payload simplicity)
    for (const [key, value] of Object.entries(additionalData).slice(0, 3)) {
      payload[key] = value;
    }
    
    // Add a floatValue if not present (for numeric analysis in TelemetryDeck)
    if (!('floatValue' in payload)) {
      payload.floatValue = Date.now() / 1000;
    }
    
    // Send the signal
    await telemetryInstance.signal(eventType, payload);
  } catch (error) {
    // Silent error in production
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

// Helper function to get system information (kept for potential future use)
function getSystemInfo(): Record<string, any> {
  const navigator = window.navigator;
  const electronProcess = (window as any).process || {};
  
  return {
    platform: navigator.platform,
    language: navigator.language,
    appVersion: isElectron ? (window.electron?.appVersion || 'unknown') : 'unknown',
    isElectron: isElectron
  };
} 