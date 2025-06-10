import { useState, useEffect } from 'react';

interface GitHubRelease {
  tag_name: string;
  name: string;
  body: string;
  html_url: string;
  published_at: string;
}

// Current app version - use Electron's version if available, or fallback to constant
const getAppVersion = (): string => {
  if (window && window.electron?.appVersion) {
    return window.electron.appVersion;
  }
  return '1.0.0'; // Fallback version for non-Electron environments
};

const CURRENT_VERSION = getAppVersion();
const GITHUB_REPO = 'gustavscirulis/snapgrid'; // Updated to use the actual repo name
const CHECK_INTERVAL = 1000 * 60 * 60 * 24; // Check once per day

export const checkForUpdates = async (): Promise<GitHubRelease | null> => {
  try {
    // If running in Electron, use its update checker
    if (window && window.electron?.checkForUpdates) {
      await window.electron.checkForUpdates();
      // The result will come through the onUpdateAvailable event
      return null;
    }
    
    // Otherwise, check directly from the renderer
    const response = await fetch(`https://api.github.com/repos/${GITHUB_REPO}/releases/latest`);
    
    if (!response.ok) {
      console.error('Error checking for updates', response.status);
      return null;
    }
    
    const latestRelease: GitHubRelease = await response.json();
    
    // Compare versions (remove 'v' prefix if present)
    const latestVersion = latestRelease.tag_name.replace(/^v/, '');
    const currentVersion = CURRENT_VERSION.replace(/^v/, '');
    
    // Simple version comparison (assumes semver format x.y.z)
    if (latestVersion > currentVersion) {
      return latestRelease;
    }
    
    return null; // No update needed
  } catch (error) {
    console.error('Failed to check for updates:', error);
    return null;
  }
};

export const useUpdateChecker = () => {
  const [updateAvailable, setUpdateAvailable] = useState<GitHubRelease | null>(null);
  const [checking, setChecking] = useState(false);
  
  const checkUpdate = async () => {
    if (checking) return;
    
    setChecking(true);
    const release = await checkForUpdates();
    if (release) {
      setUpdateAvailable(release);
    }
    setChecking(false);
  };
  
  useEffect(() => {
    // Set up listener for updates from Electron main process
    if (window && window.electron?.onUpdateAvailable) {
      const unsubscribe = window.electron.onUpdateAvailable((releaseInfo) => {
        console.log('Update available from main process:', releaseInfo);
        setUpdateAvailable(releaseInfo);
      });
      
      return unsubscribe;
    }
  }, []);
  
  useEffect(() => {
    // Check for updates when the component mounts
    checkUpdate();
    
    // Set up periodic checking
    const interval = setInterval(checkUpdate, CHECK_INTERVAL);
    
    return () => clearInterval(interval);
  }, []);
  
  return { updateAvailable, checkUpdate, checking };
};