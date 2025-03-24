## Project info

SnapGrid is an open-source desktop app for collecting, organizing, and analyzing UI screenshots. It uses AI to automatically detect UI components and patterns, making it a powerful tool for UI/UX designers, developers, and design system teams.

It's built by [@gustavscirulis](https://github.com/gustavscirulis), and all of the code is entirely AI-generated.

## Features

- **Screenshot Management** – Collect and organize your UI screenshots in a visual grid layout  
- **AI-Powered Pattern Detection** – Identify UI components and patterns using OpenAI's Vision API  
- **Smart Organization** – Search and filter your screenshots based on detected UI elements  
- **Drag & Drop** – Import screenshots via drag and drop or paste from clipboard  
- **Local Storage** – All screenshots and metadata are stored locally and can be synced with iCloud  
- **Dark Mode** – Light and dark themes for comfortable viewing  

## Installation

Download the latest release for your platform from the [releases](https://github.com/snapgrid/snapgrid/releases) page.

## Requirements

To use the AI pattern detection feature, you'll need to add your OpenAI API key in the settings. The app uses GPT-4o for vision analysis.  
You can still use the app without this feature — it just won't detect patterns.

## Privacy

SnapGrid collects anonymous usage data to help improve the application. This includes basic usage statistics and crash reports, but never your personal data or screenshots.

You can opt out of anonymous tracking at any time through the app settings.

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

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Thanks to OpenAI for their Vision API that powers the pattern detection
- Built with [Electron](https://www.electronjs.org/) and [React](https://reactjs.org/)
- UI components from [shadcn/ui](https://ui.shadcn.com/)
