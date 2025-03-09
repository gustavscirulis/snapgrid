
import React, { useEffect, useState } from 'react';
import { isElectronEnvironment } from "@/utils/electron";

type WindowControlsProps = {
  className?: string;
};

const WindowControls = ({ className = "" }: WindowControlsProps) => {
  const [isElectron, setIsElectron] = useState(false);
  
  useEffect(() => {
    // Check Electron environment on component mount
    const electronAvailable = isElectronEnvironment();
    setIsElectron(electronAvailable);
  }, []);
  
  // Don't render anything if not in Electron environment
  if (!isElectron) return null;

  const handleClose = () => {
    if (window.electron?.close) {
      window.electron.close();
    }
  };

  const handleMinimize = () => {
    if (window.electron?.minimize) {
      window.electron.minimize();
    }
  };

  const handleMaximize = () => {
    if (window.electron?.maximize) {
      window.electron.maximize();
    }
  };

  // Render the actual window control buttons
  return (
    <div className={`absolute top-1 left-2 flex items-center gap-1.5 ${className}`}>
      <button
        onClick={handleClose}
        className="w-3 h-3 rounded-full bg-red-500 hover:bg-red-600 transition-colors"
        aria-label="Close"
      />
      <button
        onClick={handleMinimize}
        className="w-3 h-3 rounded-full bg-yellow-500 hover:bg-yellow-600 transition-colors"
        aria-label="Minimize"
      />
      <button
        onClick={handleMaximize}
        className="w-3 h-3 rounded-full bg-green-500 hover:bg-green-600 transition-colors"
        aria-label="Maximize"
      />
    </div>
  );
};

export default WindowControls;
