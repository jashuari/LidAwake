# LidAwake

Keep your Mac awake while long-running tasks finish.

Requires **macOS 13 or later**, on **Intel or Apple Silicon**.

## Download and install

**[Download the latest release](https://github.com/jashuari/LidAwake/releases/latest)**

Choose the universal DMG or ZIP. No extra runtime is needed.

1. Open the DMG and drag **LidAwake** to **Applications**.
2. Eject the DMG, then open LidAwake from Applications. Look for its menu bar icon.
3. Releases are **not notarized**. If macOS blocks the first launch, go to **System Settings > Privacy & Security > Open Anyway** after attempting to open it, then confirm **Open** if you trust the download.
4. Choose **Keep Awake (lid closed)** and approve the administrator password prompt.

## Everyday use

Set a **1, 2, 4, or 8-hour timer**, choose a **battery threshold**, or enable **Launch at Login** from the menu. Turn Keep Awake off to restore normal sleep.

Closed-lid behavior varies by Mac and macOS version; test it before relying on an unattended task.

Keep your Mac ventilated and out of closed bags while active. Timer expiry and low-battery restoration may require an administrator password. The sleep setting can persist after a crash or restart; deleting the app does not reset it.

[Detailed usage and recovery](docs/usage.md) covers menu options, administrator prompts, optional passwordless setup, heat, and manual sleep restoration.

[Build, release, and CI instructions](docs/development.md)

## License

[MIT](LICENSE), copyright 2026 LidAwake contributors.
