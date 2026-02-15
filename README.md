# HatzChat (macOS)

A simple native macOS chat client for the Hatz API (https://ai.hatz.ai/v1).

## What it supports
- Chat UI (sidebar chats, delete chats)
- Local chat history stored on your Mac (~/Application Support/HatzChat/chats.json)
- Streaming responses from `/chat/completions` when `stream=true`
- Model list loaded from `/chat/models`
- Support all available models and remembers last one used
- File attachments via `/files/upload` and sending `file_uuids` with chat requests
- Reuse existing uploaded files in new chats with file picker
- App support for existing Apps from `/app/list`, though not all apps are fully supported due to API limitations. No file uploads for example.
- Hatz API Key stored in secure Mac Keychain

## How to run
1. Open `HatzChat.xcodeproj` in Xcode.
2. Click Run.
3. In the app: Settings → paste your Hatz API key → Save.
4. Start a new chat.

Or download the prebuilt Mac Application here, drop into Applications folder, run and enjoy. 

Notes:

- You must get an API key from Hatz in order to use this application. 

- The Hatz API currently has some limitations. We are unable to delete uploaded files, though they can be reused in later chats. When/if they add this, the Delete button can be setup to work. Also, we can't generate images, download files, etc. But this app should fully support all current API capabilities with Hatz.
