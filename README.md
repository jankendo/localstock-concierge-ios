# LocalStock Concierge

LocalStock Concierge is a fully local iOS inventory concierge prototype.

It keeps inventory, shopping, receipt OCR, and AI tool-call decisions on device:

- SwiftUI app shell with Home, Shopping, Inventory, Receipt, Concierge, and Settings tabs.
- SwiftData persistence for products, inventory events, shopping items, wish items, receipts, and app settings.
- Vision OCR for receipt images.
- Gemma 4 E2B-it model bootstrap that downloads `gemma-4-E2B-it.litertlm` to the app Documents directory on first launch.
- LiteRT-LM Swift package integration behind `LocalLLMService`.
- Safe JSON function-calling layer that validates model output before mutating SwiftData.
- Optional Core NFC service shell for deep-link based opening/restock flows.
- GitHub Actions unsigned IPA build on a free public macOS runner.

## Local development

This repository is designed to be edited from Windows and built on GitHub Actions.

To generate the Xcode project on macOS:

```bash
brew install xcodegen
xcodegen generate
```

To build unsigned:

```bash
xcodebuild \
  -project LocalStockConcierge.xcodeproj \
  -scheme LocalStockConcierge \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build
```

The app intentionally does not bundle the Gemma model. On first launch it downloads:

```text
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true
```

If the upstream host requires authentication or changes its URL, the Settings tab can still use an imported local model path in a future extension.
