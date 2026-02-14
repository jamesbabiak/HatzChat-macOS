# HatzChat (macOS)

A simple native macOS chat client for the Hatz API (https://ai.hatz.ai/v1).

## What it supports
- Chat UI (sidebar chats, delete chats)
- Local chat history stored on your Mac (Application Support/HatzChat/chats.json)
- Streaming responses from `/chat/completions` when `stream=true`
- Model list loaded from `/app/models`
- File attachments via `/files/upload` and sending `file_uuids` with chat requests

## How to run
1. Open `HatzChat.xcodeproj` in Xcode.
2. Click Run.
3. In the app: Settings → paste your Hatz API key → Save.
4. Start a new chat.

Notes:
- The Hatz OpenAPI file indicates file upload responses are `{}` (no documented fields),
  so the app tries to extract a UUID from the JSON response text. If it can't find one,
  it still saves the attachment locally and shows the raw response.
