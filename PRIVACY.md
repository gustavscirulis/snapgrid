# SnapGrid Privacy Policy

**Last updated:** April 11, 2026

SnapGrid is a local-first media library app. Your privacy is fundamental to how SnapGrid is built.

## Data Storage

All your media files, metadata, and thumbnails are stored locally on your device and in your personal iCloud Drive. SnapGrid does not operate any servers and has no access to your data.

- **Media files** are stored in `~/Documents/SnapGrid/` (Mac) or your iCloud Drive container (iOS).
- **App preferences** are stored locally using UserDefaults on your device.
- **API keys** you provide are stored locally on your Mac and optionally synced to your iOS device via your iCloud Drive using AES-GCM encryption.

## AI Analysis (Optional)

If you choose to enable AI analysis by providing your own API key, SnapGrid sends your images directly to the AI provider you selected:

- **OpenAI** (api.openai.com)
- **Anthropic** (api.anthropic.com)
- **Google Gemini** (generativelanguage.googleapis.com)
- **OpenRouter** (openrouter.ai)

Image data is sent directly from your device to the provider's API using your personal API key. SnapGrid does not proxy, store, or have access to this data in transit. Each provider's own privacy policy governs how they handle your data.

You can disable AI analysis at any time by removing your API key in Settings.

## Data Collection

SnapGrid collects **no analytics, telemetry, or usage data**. There are:

- No crash reporting SDKs
- No analytics frameworks
- No advertising identifiers
- No user tracking of any kind

## Third-Party Services

SnapGrid does not include any third-party SDKs. All network requests are made using Apple's built-in frameworks (URLSession) directly to the services listed above, only when you explicitly configure them.

When importing media from X/Twitter URLs, SnapGrid accesses Twitter's public syndication API to retrieve the media you requested.

## iCloud Sync

SnapGrid uses your personal iCloud Drive to sync media and settings between your Mac and iOS devices. This sync happens entirely through Apple's iCloud infrastructure using your Apple Account. SnapGrid has no server-side component and cannot access your iCloud data.

## Children's Privacy

SnapGrid is not directed at children under 13 and does not knowingly collect personal information from children.

## Changes

We may update this policy from time to time. The latest version will always be available at [snapgrid.app/privacy](https://snapgrid.app/privacy).

## Contact

If you have questions about this privacy policy, contact us at privacy@snapgrid.app.
