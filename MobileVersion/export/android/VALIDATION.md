# Android Validation Checklist

Use this checklist after opening `MobileVersion/` in Godot 4.3+.

- Install Android export templates for the exact Godot version in use.
- Configure Android SDK and JDK paths in Godot editor settings.
- Create or verify the debug keystore.
- Keep the package name in `export_presets.cfg` updated before shipping.
- Export `Android Debug` to `export/android/slime-isa-debug.apk`.
- Install the APK on one physical Android phone.
- Confirm fullscreen/immersive landscape display.
- Confirm the virtual joystick respects safe areas and thumb reach.
- Confirm action buttons trigger jump, roll, interact, ability, and pause.
- Confirm coins/berries save to `user://savegame.json` and remain collected after relaunch.
- Confirm pause/background saves and clears stuck touch state.
- Confirm DebugOverlay shows FPS, position, input vectors/actions, camera limits, and save status.
