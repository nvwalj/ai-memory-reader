# Licensing notes

The public source code of AI Memory Reader is offered under **GPL-3.0** (see `LICENSE`).

## Distribution channels

Two channels carry the same binary, under different licenses to the *recipient*:

| Channel | Recipient license | Notes |
|---|---|---|
| **GitHub releases** (`AIMemoryReader-vX.Y.Z-universal.zip`) | GPL-3.0 | The free, ad-hoc-signed binary. Recipients have full GPL rights: copy, modify, redistribute, with source. |
| **Mac App Store** (planned) | Proprietary (Apple's standard EULA) | The sandboxed, notarized binary distributed by Apple. Recipients accept Apple's standard end-user license. |

This is a standard **dual-licensing** arrangement (the same pattern used by SQLite, MySQL, Qt, and Redis historically): the copyright holder offers the same source under two different terms to different audiences.

## Why this is legal

The GPL-3.0 binds **downstream recipients** of the binary, not the copyright holder. As the sole author of the original code in this repository, [nvwalj](https://github.com/nvwalj) retains full copyright and may distribute the code under any license, including a separate proprietary license to Apple for App Store submission.

Third-party Swift packages used in the build are all under permissive licenses compatible with both GPL-3.0 and Apple's terms:

- [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) — MIT
- [Splash](https://github.com/JohnSundell/Splash) — MIT

## What this means in practice

- **You can fork this repo and redistribute under GPL-3.0** freely. Your fork remains GPL.
- **You cannot submit your fork to the Mac App Store** under GPL-3.0 — Apple's terms conflict with GPL's redistribution clauses. You would need to either change the license (you can't, because your modifications inherit GPL) or contact nvwalj for a separate commercial license.
- **The Mac App Store build is the same source code**, but distributed under a different (Apple-required) license. You are not getting "different software" — you're getting a sandboxed, Apple-reviewed binary of the same code.

## Questions

If you want to ship a closed-source product built on AI Memory Reader code, open an issue or email — commercial licensing is available.
