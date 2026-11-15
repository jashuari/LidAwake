# Using LidAwake

[Back to the README](../README.md)

## Installation notes

The universal DMG and ZIP contain the same app for Intel and Apple Silicon Macs running macOS 13 or later. No Xcode, Swift, Homebrew, or separate runtime is needed. For the ZIP, unzip it and move `LidAwake.app` to Applications. The app appears in the menu bar; there is no Dock window.

Releases are ad-hoc signed, not Developer ID signed or notarized. If macOS blocks the first launch, attempt to open the installed app, then use **System Settings > Privacy & Security > Open Anyway** and confirm **Open**, if you trust the download. See [Apple’s instructions](https://support.apple.com/en-us/102445). Managed Macs may not allow this override.

Installing and opening LidAwake does not enable sleep prevention or modify sudoers, privilege settings, or power settings. Enable **Keep Awake (lid closed)** explicitly. Closed-lid behavior depends on the Mac and macOS version and is not guaranteed on every device or release. Try closing and reopening the lid while the Mac is nearby before relying on an unattended task.

## How it works


`caffeinate` and idle-sleep assertions do not generally override lid-close sleep. LidAwake runs the fixed command `/usr/bin/pmset -a disablesleep 1` with administrator authorization to disable system sleep, and holds a `PreventUserIdleSystemSleep` assertion. Turning it off runs `/usr/bin/pmset -a disablesleep 0`. This changes a **system-wide setting for all power sources**, affecting more than lid-close behavior.

The app reads `pmset -g` at launch and whenever the menu opens. If `SleepDisabled` is already `1`, it adopts that active state, including a setting left by a crash or another tool. Turning off or quitting then requests `disablesleep 0`; it does not restore a separately saved previous value. Avoid running multiple sleep-control tools at once.

The app has no telemetry, account, or network service. It uses Apple's built-in tools and frameworks.

## Menu

- **Status line**: active state, remaining timer, and battery percentage when available.
- **Keep Awake (lid closed)**: enable or disable sleep prevention.
- **Keep awake for…**: 1, 2, 4, or 8 hours, or Indefinitely. Selecting a duration while active resets the timer.
- **Auto-disable on battery below**: Off, 10%, 20% (default), or 30%. The battery is checked every 60 seconds. This only applies while running on battery; Macs without an internal battery do not have this protection.
- **Launch at Login**: opt in using `SMAppService`. Run the installed app from Applications; macOS may ask for approval in System Settings > General > Login Items.
- **Quit LidAwake**: attempts to restore normal sleep before exiting. If restoration fails or is cancelled, the menu Quit action offers Cancel or Quit Anyway.

## Administrator prompts and automatic turn-off

Enabling and disabling sleep require administrator authorization. Each change first tries `sudo -n` for the exact `pmset` command; this can succeed with a matching sudoers rule or available cached authorization. Otherwise the app uses the macOS administrator password dialog through `osascript`. Cancelling that dialog leaves the current power setting unchanged.

**Timer expiry and low-battery turn-off can also require this dialog.** With the lid closed or nobody available to enter the password, sleep may stay disabled. These controls are not a guaranteed unattended safeguard. Timers are in memory and are not restored after a restart. Turning on Launch at Login does not make automatic turn-off passwordless.

### Optional manual setup for passwordless toggling

This step is optional and is never performed by the app or installer. It grants your user permission to run the two exact commands as root without a password, including from other processes running as that user. Use it only if you understand and accept that permission. A manually configured rule lets timer and battery turn-off attempt restoration without waiting for a password prompt; the app must still be running.

In Terminal, find your short user name with `whoami`, then open a dedicated sudoers file:

```sh
sudo visudo -f /etc/sudoers.d/lidawake
```

Add the following line, replacing `yourname` with that short user name. Keep the command arguments exact; do not use wildcards or grant unrestricted access to `pmset`:

```sudoers
yourname ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

Save and exit, then validate the complete configuration with `sudo visudo -c`. Do not bypass validation errors. To remove only this optional rule:

```sh
sudo rm /etc/sudoers.d/lidawake
```

## Heat, battery, and recovery

- While active, normal system sleep is disabled. Battery drain and heat can increase, including with the lid closed. **Do not put an active Mac in a closed bag or block ventilation.** Thermal protection, shutdown, and hardware behavior can still interrupt work.
- Do not rely on the battery threshold as the only protection: checks happen once a minute, the app must be running, and restoring sleep may need a password. AC power does not eliminate heat risk.
- Treat the `disablesleep` setting as persistent: it can remain after the app exits or crashes and across restarts. Force Quit, `kill -9`, a crash, shutdown timing, or cancelled authorization can prevent cleanup. The app attempts restoration on normal termination and SIGTERM/SIGINT, but success is not guaranteed.
- Deleting the app does not reset the power setting. Turn sleep prevention off first, disable Launch at Login if enabled, then quit and remove the app.

To restore normal sleep manually in Terminal:

```sh
sudo /usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -g
```

Check the output for `SleepDisabled`: `0`, or no such line after a successful command, indicates that this flag is no longer enabled. Confirm normal sleep behavior on your Mac before transporting it.

