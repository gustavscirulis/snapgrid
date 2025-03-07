
import React from 'react';

type WindowControlsProps = {
  className?: string;
};

const WindowControls = ({ className = "" }: WindowControlsProps) => {
  // Always return null to hide these buttons as we're using the native title bar
  return null;
};

export default WindowControls;
