# LocalStock Concierge

LocalStock Concierge is an iOS inventory concierge prototype with local AI and optional Supabase household sharing.

It keeps receipt OCR, Gemma inference, and AI tool-call decisions on device, while inventory data can be shared through a Supabase database protected by Row Level Security:

- SwiftUI app shell with Home, Shopping, Inventory, Receipt, Concierge, and Settings tabs.
- SwiftData persistence as an offline cache for products, inventory events, shopping items, wish items, receipts, and app settings.
- Supabase Auth magic-link login plus household-scoped tables for shared inventory.
- Household-shared shopping and wish lists backed by Supabase.
- Vision OCR for receipt images.
- Gemma 4 E2B-it model bootstrap that downloads `gemma-4-E2B-it.litertlm` to the app Documents directory on first launch.
- LiteRT-LM Swift package integration behind `LocalLLMService`.
- Safe JSON function-calling layer that validates model output before mutating SwiftData.
- Optional Core NFC service shell for deep-link based opening/restock flows.
- Generated app icon and in-app concierge artwork.
- GitHub Actions unsigned IPA build on a free public macOS runner.

## Supabase setup

Run `supabase/schema.sql` in the Supabase SQL Editor. The schema creates `localstock_*` tables, enables RLS, scopes all reads/writes by household membership, and adds an authenticated `localstock_join_household` RPC for invite-code joining. Products, inventory events, shopping items, wish items, and receipt records are synchronized through those household-scoped tables.

Pass the values as Xcode build settings, or create a local `Config/Supabase.xcconfig` from the example file and wire it into your local Xcode project:

```xcconfig
SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_YOUR_KEY
```

The publishable key is safe in the client only because RLS is enabled. Do not put a service-role key in the iOS app or in this public repository.

For GitHub Actions builds, add repository secrets named `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. The unsigned IPA workflow injects them as build settings without committing secrets.

If the IPA was built without those repository secrets, open Settings > Supabase共有 after installing the app and save the Supabase URL plus a publishable key on the device. The app rejects `sb_secret_` and legacy `service_role` keys; shared access still depends on running `supabase/schema.sql` and keeping RLS enabled.

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
