# Avatar motion snapshot

This directory contains the exact avatar code and guide artwork used by the learning application before its standalone extraction on 2026-09-15.

The files were copied from this repository’s existing local `avatar-motion/Sources` and `avatar-motion/Assets` and verified byte-for-byte against the pre-extraction backup. They are intentionally preserved without modifications so the learning application retains its existing appearance and animation independently of later changes to the lab or avatar application.

Only the five Swift source files compiled by the learning application and the five guide assets already packaged by `prepare-guide-resources.sh` are included. The original rig manifest is preserved; the learning guide continues to select its supported poses in its existing code.

To verify the snapshot from this directory:

```sh
shasum -a 256 -c SHA256SUMS
```
