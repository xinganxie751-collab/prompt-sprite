# Prompt Sprite

Prompt Sprite is an always-on-top Windows desktop widget that turns images, videos, screen recordings, text, and links into reusable prompts. Drop a reference onto the widget and get a prompt for an image, a video, or a web implementation.

## Get started

1. Download and extract the whole repository. Keep its folder structure intact.
2. Double-click **Launch Prompt Sprite.cmd**. The widget opens expanded in the center of the screen. If it docks later, hover over its edge tab or select Prompt Sprite in the Windows taskbar.
3. Open **Model provider** and choose Codex, Doubao, DeepSeek, or manual export.
4. In the same panel, choose **Interface and output language**, then **Save**. English is the default for new installations. You can also use Simplified Chinese, Japanese, Korean, Russian, or German. Your choice is saved and applies to future prompts and manual export instructions.

## Model providers

| Provider | Setup |
| --- | --- |
| Codex | Install the Codex CLI and sign in with your ChatGPT account. |
| Doubao | Enter your Ark API key and a vision model ID or endpoint. |
| DeepSeek | Enter your DeepSeek API key. This integration requests the `deepseek-flash` model. |
| Manual export | Prepare instructions and keyframes locally for a chat service of your choice. No account is needed to export. |

The widget runs on Windows x64 with Windows PowerShell 5.1. The built-in browser uses Microsoft Edge WebView2 Runtime. Extracting frames from video files or supported public Douyin players requires Node.js 20 or later and Chrome or Edge.

## Use it

- Drop a file, paste a link or text, or record an area of the screen. Select **Copy prompt** when the result is ready.
- Leave the widget idle and it docks as a narrow tab. Hover over the tab to reveal the widget. You can also drop files directly onto the tab.
- If a Douyin share link cannot provide frames directly, open it in **Browser**, play the video, and select **Record**. Confirm the detected player area or select an area yourself. Press **Ctrl + Shift + F10** or select **Stop recording** to finish. Recordings contain up to 30 seconds of video without audio.
- Change the prompt type and generate again to reuse the current reference.

## Data and storage

Recordings are stored temporarily on your computer. When generating automatically, Prompt Sprite passes the selected text, images, and keyframes to your chosen provider and uses its quota. For ordinary web pages in Doubao or DeepSeek mode, attach screenshots or a recording as visual references. Manual export saves instructions and frames locally. API keys are encrypted for the current Windows user. The built-in browser keeps its profile in the local application data directory.

See [webview2](webview2/) for WebView2 SDK license information and third-party notices.
