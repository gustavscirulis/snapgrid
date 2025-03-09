
// Helper function to get video dimensions and generate a thumbnail
export function getVideoDimensions(videoSrc: string): Promise<{
  width: number;
  height: number;
  duration: number;
  posterUrl: string;
}> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    
    // Set up event handlers
    video.onloadedmetadata = () => {
      const width = video.videoWidth;
      const height = video.videoHeight;
      const duration = video.duration;
      
      // Generate a poster image at the 1 second mark or at the start if shorter
      const seekTime = duration > 1 ? 1 : 0;
      video.currentTime = seekTime;
    };
    
    video.onseeked = () => {
      // Create a canvas to draw the video frame
      const canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      
      // Draw the video frame to the canvas
      const ctx = canvas.getContext('2d');
      if (ctx) {
        ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
        
        // Convert the canvas to a data URL
        const posterUrl = canvas.toDataURL('image/jpeg');
        
        // Clean up
        video.src = '';
        
        // Resolve with the video dimensions and poster URL
        resolve({
          width: video.videoWidth,
          height: video.videoHeight,
          duration: video.duration,
          posterUrl,
        });
      } else {
        reject(new Error('Could not get canvas context'));
      }
    };
    
    // Error handling
    video.onerror = () => {
      reject(new Error('Error loading video'));
    };
    
    // Start loading the video
    video.src = videoSrc;
    video.load();
  });
}
