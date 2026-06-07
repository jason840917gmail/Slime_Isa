# Slime Isa Mobile

Godot Android/mobile version of Slime Isa.

## Android Export

Use an Android virtual device with **API 35**. The debug APK exports `arm64-v8a` for physical devices and `x86_64` for Android Emulator.

### Export Debug APK

PowerShell:

```powershell
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot"
$env:ANDROID_HOME = "C:\Users\User\AppData\Local\Android\Sdk"
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:ANDROID_HOME\build-tools\35.0.0;$env:Path"

& "C:\Users\User\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe" `
  --headless `
  --path "D:\projects\Slime isa\MobileVersion" `
  --export-debug "Android Debug" `
  "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

APK output:

```text
export/android/slime-isa-debug.apk
```

### Deploy To Android Emulator

Start the virtual device first, then run:

```powershell
adb devices
adb install -r "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

If more than one device is connected:

```powershell
adb -s emulator-5554 install -r "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```

### Verify APK Signature

```powershell
& "C:\Users\User\AppData\Local\Android\Sdk\build-tools\35.0.0\apksigner.bat" verify --verbose "D:\projects\Slime isa\MobileVersion\export\android\slime-isa-debug.apk"
```
