# Compilación, Tests y Release

## Requisitos

- macOS 15+ (Sequoia)
- Xcode 16+
- Swift 6.0+
- Command Line Tools: `xcode-select --install`

## Compilar

### App + Core

```bash
# Abrir proyecto en Xcode
open MacMule.xcodeproj

# O compilar via xcodebuild
xcodebuild -scheme MacMule -configuration Debug build
xcodebuild -scheme MacMule -configuration Release build
```

### Solo Paquete Core (headless)

```bash
cd MacMuleCore
swift build
swift build -c release
```

## Tests

### Core tests

```bash
cd MacMuleCore
swift test
swift test --filter ED2KLinkTests
```

### Test Coverage

```bash
swift test --enable-code-coverage
xcrun llvm-cov show \
  .build/debug/MacMuleCorePackageTests.xctest/Contents/MacOS/MacMuleCorePackageTests \
  -instr-profile=.build/debug/codecov/default.profdata
```

## Release

### Generar Release Build

```bash
xcodebuild -scheme MacMule -configuration Release \
  -derivedDataPath build archive \
  -archivePath build/MacMule.xcarchive

# Exportar .app
xcodebuild -exportArchive \
  -archivePath build/MacMule.xcarchive \
  -exportPath build/MacMule \
  -exportOptionsPlist exportOptions.plist

# Firmar y notarizar (requiere Apple Developer ID)
codesign --deep --force --verify --verbose \
  --options runtime \
  --sign "Developer ID Application: Tu Nombre (XXXXXXXXXX)" \
  build/MacMule/MacMule.app

ditto -c -k --keepParent build/MacMule/MacMule.app build/MacMule.zip

xcrun notarytool submit build/MacMule.zip \
  --apple-id "email@ejemplo.com" \
  --team-id "XXXXXXXXXX" \
  --password "@keychain:AC_PASSWORD" \
  --wait
```

### Tags

```bash
git tag -a v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

## CI

### GitHub Actions (ejemplo)

```yaml
name: Build & Test
on: [push, pull_request]
jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - name: Build Core
        run: cd MacMuleCore && swift build
      - name: Test Core
        run: cd MacMuleCore && swift test
      - name: Build App
        run: xcodebuild -scheme MacMule build
```

## Referencias

- [Project Structure](02-project-structure.md) — árbol de directorios
- [Troubleshooting](03-troubleshooting.md) — problemas comunes
