const { notarize } = require('electron-notarize');

// Using CommonJS format to avoid module cycle error
module.exports = async function notarizing(context) {
  const { electronPlatformName, appOutDir } = context;
  
  // Only notarize macOS builds
  if (electronPlatformName !== 'darwin') {
    return;
  }

  console.log('Notarizing macOS application...');

  const appName = context.packager.appInfo.productFilename;
  const appPath = `${appOutDir}/${appName}.app`;

  // Environment variables should be set in your CI/CD pipeline or locally
  // APPLE_ID: Your Apple ID email
  // APPLE_APP_SPECIFIC_PASSWORD: App-specific password for your Apple ID
  // APPLE_TEAM_ID: Your Apple Developer Team ID
  
  try {
    await notarize({
      appBundleId: 'com.snapgrid.app',
      appPath,
      appleId: process.env.APPLE_ID,
      appleIdPassword: process.env.APPLE_APP_SPECIFIC_PASSWORD,
      teamId: process.env.APPLE_TEAM_ID,
    });
    console.log('Notarization completed successfully!');
  } catch (error) {
    console.error('Notarization failed:', error);
    throw error;
  }
} 