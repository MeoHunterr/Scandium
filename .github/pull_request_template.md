## Description

Briefly describe the purpose and context of this pull request.

Closes # (issue number)

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💄 UI/UX enhancement (visual styling, layout, animations, theming)
- [ ] 🔒 Security fix / FOSS compliance (Keychain, ATS scoping, trademark safety)
- [ ] ⚡ Performance optimization (memory, background queue, audio caching)
- [ ] 📝 Documentation update (guides, README, issue templates)

## How Has This Been Tested?

- **Device**: (e.g., iPhone 13 Pro, iPad Air 5)
- **iOS Version**: (e.g., iOS 15.4, iOS 16.5, iOS 17.0)
- **Installation Method**: (e.g., TrollStore 2, SideStore, AltStore, Xcode)
- **Verification**:
  - [ ] Tested audio playback and background audio engine
  - [ ] Tested offline caching and library persistence
  - [ ] Tested alternate app icon switching
  - [ ] Tested international / Vietnamese language localization

## Checklist

- [ ] My code follows the project's clean coding standards (no placeholder or superfluous AI comments).
- [ ] I have verified that backward compatibility with iOS 15.0+ is maintained.
- [ ] The binary builds cleanly with `xtool dev build -c release`.
- [ ] I have pseudo-signed and verified Mach-O headers with `./scripts/build_ipa.sh`.
- [ ] All trademarks and third-party terms respect FOSS compliance.
