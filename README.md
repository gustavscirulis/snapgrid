## Project info

SnapGrid is an open-source desktop app for collecting, organizing, and analyzing UI screenshots. It uses AI to automatically detect UI components and patterns, making it a powerful tool for designers and developers.

![SnapGrid Preview](assets/preview.png)

It's built by [@gustavscirulis](https://github.com/gustavscirulis), and all of the code is entirely AI-generated.

## Features

- **Screenshot Management** – Collect and organize your UI screenshots in a visual grid layout
- **AI-Powered Pattern Detection** – Identify UI components and patterns using OpenAI's Vision API  
- **Smart Organization** – Search and filter your screenshots based on detected UI elements  
- **Fast Local Storage** – All screenshots and metadata are stored locally and can be synced with iCloud  

## Installation

Download the latest release for your platform from the [releases](https://github.com/gustavscirulis/snapgrid/releases) page.

### macOS Users
- If you have an Intel Mac (2020 or earlier), download `SnapGrid.dmg`
- If you have an Apple Silicon Mac (M1/M2/M3), download `SnapGrid-arm64.dmg`
- Not sure? Click Apple menu () > About This Mac. Under "Chip" or "Processor", you'll see which type you have

## Requirements

To use the AI pattern detection feature, you'll need to add your OpenAI API key in the settings. The app uses GPT-4.1-mini for vision analysis. You can still use the app without this feature — it just won't detect patterns.

## Privacy

SnapGrid is built with privacy in mind:

- **Local-first by design**: All screenshots, metadata, and app data are stored locally on your device. Nothing is uploaded or stored remotely.
- **Optional AI analysis**: If enabled, screenshots are temporarily sent to OpenAI’s Vision API for pattern detection. This feature is optional and can be turned off at any time in the settings.
- **Anonymous usage analytics**: SnapGrid collects basic, anonymous usage stats and crash reports to help improve the app. No personal data or screenshots are ever collected. You can opt out of tracking in the settings.

## File storage

SnapGrid stores files in the following locations:

- **macOS**: `~/Documents/SnapGrid/`  
- **Other platforms**: in the app's user data directory

Inside that folder:

- `images/` – All media files (PNG screenshots and MP4 videos)  
- `metadata/` – JSON metadata for each media item  
- `.trash/` – Deleted items are moved here (same structure as above)

## Development

SnapGrid is built with:

- Electron  
- Vite  
- TypeScript  
- React  
- shadcn-ui  
- Tailwind CSS

### Setting Up Development Environment

```sh
# Clone the repository
git clone https://github.com/snapgrid/snapgrid.git

# Navigate to the project directory
cd snapgrid

# Install dependencies
npm install

# Start development server
npm run electron:dev
```

### Building for Production

```sh
# Build for production
npm run electron:build
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0) - see the LICENSE file for details. This license ensures that all modifications to this code remain open source.

## Acknowledgments

- Thanks to [Cursor](https://cursor.com) and [Loveable](https://loveable.dev) teams for building the AI code generation tools that made this project possible
- Thanks to [Midjourney](https://www.midjourney.com/) for the app icon
- Thanks to OpenAI for their Vision API that powers the pattern detection
- Built with [Electron](https://www.electronjs.org/) and [React](https://reactjs.org/)
- UI components from [shadcn/ui](https://ui.shadcn.com/)
