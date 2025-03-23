# SnapGrid

## Project info

SnapGrid is an open-source desktop application designed for collecting, organizing, and analyzing UI screenshots. It uses AI to automatically detect UI patterns and components, making it an invaluable tool for UI/UX designers, developers, and design system teams.

It's built by @gustavscirulis and all of the code is entirely AI-generated.

## Features

- **Screenshot Management**: Collect and organize your UI screenshots in a visual grid layout
- **AI-Powered Pattern Detection**: Automatically identify common UI components and patterns using OpenAI's Vision API
- **Smart Organization**: Search and filter your screenshots based on detected UI patterns
- **Drag & Drop Support**: Easily import screenshots via drag and drop or clipboard paste
- **Cross-Platform**: Works on macOS, Windows, and Linux (primary focus on macOS)
- **Local Storage**: All your screenshots and metadata are stored locally and can be synced using iCloud
- **Dark Mode Support**: Beautiful dark and light themes for comfortable viewing

### Installation

Download the latest release for your platform from the [Releases](https://github.com/snapgrid/snapgrid/releases) page.

### Requirements

- **OpenAI API Key**: To use the AI pattern detection feature, you'll need to add your OpenAI API key in the settings. The app uses GPT-4o for vision analysis. The app can still be used without this feature.


## File Storage Structure

SnapGrid stores files in the following locations:

- **macOS**: `~/Documents/SnapGrid/`
- **Other platforms**: In the app's user data directory

Within this directory:
- `images/` - Contains all media files (PNG images and MP4 videos)
- `metadata/` - Contains JSON metadata files for each media item
- `.trash/` - Trash directory with the same structure (images/ and metadata/ subdirectories)

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
