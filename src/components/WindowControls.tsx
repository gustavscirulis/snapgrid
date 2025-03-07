
import React from 'react';

type WindowControlsProps = {
  className?: string;
};

const WindowControls = ({ className = "" }: WindowControlsProps) => {
  const isElectron = window && typeof window.electron !== 'undefined';
  
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

  return (
    <div className={`absolute left-4 top-1/2 -translate-y-1/2 flex items-center gap-1.5 z-20 ${className}`}>
      <button
        onClick={handleClose}
        className="w-3 h-3 rounded-full bg-[#FF5F57] hover:brightness-90 transition-all"
        aria-label="Close"
      />
      <button
        onClick={handleMinimize}
        className="w-3 h-3 rounded-full bg-[#FFBD2E] hover:brightness-90 transition-all"
        aria-label="Minimize"
      />
      <button
        onClick={handleMaximize}
        className="w-3 h-3 rounded-full bg-[#28C840] hover:brightness-90 transition-all"
        aria-label="Maximize"
      />
    </div>
  );
};

export default WindowControls;
