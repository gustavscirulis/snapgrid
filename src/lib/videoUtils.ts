// Helper function to get video dimensions and generate a thumbnail
export function getVideoDimensions(videoSrc: string): Promise<{
  width: number;
  height: number;
  duration: number;
  posterUrl: string;
}> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');

    // Ensure we load the metadata
    video.preload = 'metadata';

    // Set cross-origin attributes to avoid issues
    video.crossOrigin = 'anonymous';

    // Add event handlers
    video.onloadedmetadata = () => {
      console.log('Video metadata loaded:', {
        width: video.videoWidth,
        height: video.videoHeight,
        duration: video.duration
      });

      const width = video.videoWidth;
      const height = video.videoHeight;
      const duration = video.duration;

      // Generate a poster image at the 1 second mark or at the start if shorter
      const seekTime = duration > 1 ? 1 : 0;

      try {
        video.currentTime = seekTime;
      } catch (err) {
        console.error('Error seeking video', err);
        // If seeking fails, try to generate poster from current frame
        generatePoster();
      }
    };

    video.onseeked = generatePoster;

    // Handle errors
    video.onerror = (e) => {
      console.error('Video loading error:', video.error);
      reject(new Error(`Video error: ${video.error?.message || 'Unknown error'}`));
    };

    function generatePoster() {
      try {
        // Create a canvas to draw the video frame
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth || 640; // Fallback width if not available
        canvas.height = video.videoHeight || 360; // Fallback height if not available

        // Draw the video frame to the canvas
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

          // Convert the canvas to a data URL (JPEG for smaller size)
          const posterUrl = canvas.toDataURL('image/jpeg', 0.8);

          // Clean up
          video.src = '';

          // Resolve with the video dimensions and poster URL
          resolve({
            width: video.videoWidth || 640,
            height: video.videoHeight || 360,
            duration: video.duration || 0,
            posterUrl,
          });
        } else {
          reject(new Error('Could not get canvas context'));
        }
      } catch (err) {
        console.error('Error generating poster:', err);
        reject(err);
      }
    }

    // Set the video source and start loading
    video.src = videoSrc;
    video.load();
  });
}