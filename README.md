## Project info

SnapGrid is an open-source desktop app for collecting, organizing, and analyzing images and videos. It uses AI to automatically categorize your visual content, making it easy to search and manage large collections.

![SnapGrid Preview](assets/preview.png)

It's built by [@gustavscirulis](https://github.com/gustavscirulis), and all of the code is entirely AI-generated.

### Use cases

- **UI/UX Design** – Collect reference screenshots, organize design inspiration, and track UI patterns across apps
- **Mood Boarding** – Gather visual references for creative projects and organize them into themed spaces
- **Development** – Save and categorize UI states, bugs, and visual regression captures
- **Content Creation** – Manage image and video assets with AI-powered tagging and search
- **Research** – Organize visual research material and let AI surface patterns across collections

## Features

- **Image & Video Management** – Collect and organize images and videos in a visual grid layout
- **Spaces** – Organize media into collections with drag-and-drop support and per-space export
- **Multi-Provider AI Analysis** – Automatically categorize content using OpenAI, Claude (Anthropic), Google Gemini, or OpenRouter
- **Custom AI Instructions** – Configure custom analysis prompts per space for tailored insights
- **Smart Organization** – Search and filter your library based on AI-detected categories and patterns
- **iOS Shortcut Import** – Export an iOS Shortcut from settings to import media from your phone
- **Fast Local Storage** – All media and metadata are stored locally and can be synced with iCloud

## Installation

Download the latest release for your platform from the [releases](https://github.com/gustavscirulis/snapgrid/releases) page.

### macOS Users
- If you have an Intel Mac (2020 or earlier), download `SnapGrid.dmg`
- If you have an Apple Silicon Mac (M1/M2/M3), download `SnapGrid-arm64.dmg`
- Not sure? Click Apple menu () > About This Mac. Under "Chip" or "Processor", you'll see which type you have

## Requirements

To use the AI analysis feature, you'll need to add an API key for at least one supported provider in the settings: OpenAI, Anthropic (Claude), Google Gemini, or OpenRouter. You can choose your preferred provider and model from the settings panel. You can still use the app without AI — it works great as a media organizer on its own.

## Privacy

SnapGrid is built with privacy in mind:

- **Local-first by design**: All media, metadata, and app data are stored locally on your device. Nothing is uploaded or stored remotely.
- **Optional AI analysis**: If enabled, images are temporarily sent to your chosen AI provider (OpenAI, Anthropic, Google Gemini, or OpenRouter) for categorization. This feature is optional and can be turned off at any time in the settings.
- **Anonymous usage analytics**: SnapGrid collects basic, anonymous usage stats and crash reports to help improve the app. No personal data or media are ever collected. You can opt out of tracking in the settings.

## File storage

SnapGrid stores files in the following locations:

- **macOS**: `~/Documents/SnapGrid/`  
- **Other platforms**: in the app's user data directory

Inside that folder:

- `images/` – All media files (PNG images and MP4 videos)
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
- Thanks to [OpenAI](https://openai.com/), [Anthropic](https://anthropic.com/), [Google Gemini](https://deepmind.google/technologies/gemini/), and [OpenRouter](https://openrouter.ai/) for their AI APIs that power image categorization
- Built with [Electron](https://www.electronjs.org/) and [React](https://reactjs.org/)
- UI components from [shadcn/ui](https://ui.shadcn.com/)
