// Helper function to get video dimensions and generate a thumbnail
export function getVideoDimensions(videoSrc: string): Promise<{
  width: number;
  height: number;
  duration: number;
  posterUrl: string;
}> {
  return new Promise((resolve, reject) => {
    if (!videoSrc) {
      reject(new Error('Video source is empty'));
      return;
    }

    const video = document.createElement('video');

    // Ensure we load the metadata
    video.preload = 'metadata';

    // Set cross-origin attributes to avoid issues
    video.crossOrigin = 'anonymous';

    // Add event handlers
    video.onloadedmetadata = () => {

      const width = video.videoWidth;
      const height = video.videoHeight;
      const duration = video.duration;

      // Always generate poster from the first frame
      const seekTime = 0;

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
      const errorMessage = video.error?.message || 'Unknown error';
      // Only log as error if it's not the empty src attribute case
      if (video.error?.code !== 4) {
        console.error('Video loading error:', video.error);
      }
      // For empty src, provide default dimensions
      if (video.error?.code === 4) {
        resolve({
          width: 640,
          height: 360,
          duration: 0,
          posterUrl: '',
        });
      } else {
        reject(new Error(`Video error: ${errorMessage}`));
      }
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
          video.removeAttribute('src'); // Use removeAttribute instead of setting to empty string
          video.load(); // Ensure the video element is properly reset

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

/**
 * Captures frames from a video at specific percentages of the duration
 * @param videoSrc The URL or data URL of the video
 * @param percentages Array of percentages (0-1) at which to capture frames
 * @returns Promise resolving to an array of frame data URLs
 */
export function captureVideoFrames(
  videoSrc: string,
  percentages: number[] = [0.33, 0.66]
): Promise<string[]> {
  return new Promise((resolve, reject) => {
    if (!videoSrc) {
      reject(new Error('Video source is empty'));
      return;
    }

    const video = document.createElement('video');
    video.preload = 'metadata';
    video.crossOrigin = 'anonymous';
    
    const frames: string[] = [];
    let percentageIndex = 0;

    video.onloadedmetadata = () => {
      // First, try to seek to the first percentage point
      if (percentages.length > 0 && video.duration) {
        try {
          // Calculate the time to seek to based on the percentage
          const seekTime = video.duration * percentages[percentageIndex];
          video.currentTime = seekTime;
        } catch (err) {
          console.error('Error seeking video', err);
          reject(err);
        }
      } else {
        reject(new Error('No percentages provided or video has no duration'));
      }
    };

    video.onseeked = () => {
      try {
        // Create a canvas to draw the video frame
        const canvas = document.createElement('canvas');
        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;

        // Draw the video frame to the canvas
        const ctx = canvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          
          // Convert the canvas to a data URL (JPEG for smaller size)
          const frameUrl = canvas.toDataURL('image/jpeg', 0.9);
          frames.push(frameUrl);
          
          // Move to the next percentage if there is one
          percentageIndex++;
          if (percentageIndex < percentages.length) {
            try {
              video.currentTime = video.duration * percentages[percentageIndex];
            } catch (err) {
              console.error('Error seeking to next frame', err);
              // Even if seeking to next frame fails, we still have some frames
              cleanupAndResolve();
            }
          } else {
            // We've captured all frames, clean up and resolve
            cleanupAndResolve();
          }
        } else {
          reject(new Error('Could not get canvas context'));
        }
      } catch (err) {
        console.error('Error capturing frame:', err);
        reject(err);
      }
    };

    // Handle errors
    video.onerror = (e) => {
      const errorMessage = video.error?.message || 'Unknown error';
      console.error('Video loading error:', video.error);
      reject(new Error(`Video error: ${errorMessage}`));
    };

    function cleanupAndResolve() {
      // Clean up
      video.removeAttribute('src');
      video.load();
      resolve(frames);
    }

    // Set the video source and start loading
    video.src = videoSrc;
    video.load();
  });
}