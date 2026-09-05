# Memory Alive — Native iPhone Technical Spike

This repository is now moving from the browser proof-of-concept to a native iPhone build focused on exactly three capabilities:

1. Restore an old photo
2. Colourise a black-and-white photo
3. Bring one portrait face to life

## Phone-only rule

All production inference must run on the iPhone. No cloud inference, no per-use API, no upload requirement.

## Native stack

- SwiftUI / PhotosUI
- Vision for face detection and landmarks
- Core ML for restoration, colourisation and portrait animation models
- Core Image / Metal-backed rendering
- AVFoundation for final video export

## Model direction

- Restoration: GFPGAN-style face restoration + Real-ESRGAN general restoration, converted/optimised for Core ML
- Colourisation: compact semantic colourisation model distilled for mobile deployment; DeOldify is not the production target
- Portrait animation: MobilePortrait-style mobile neural head animation; LivePortrait is a quality/control benchmark

The source tree is under `ios/MemoryAlive/`.

## Important

The native target requires Xcode on macOS to compile, sign and run on a physical iPhone. The GitHub Pages browser demo remains in `index.html` only as the earlier proof-of-concept; it is not the product path.
