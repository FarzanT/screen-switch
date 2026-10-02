# Acknowledgments

Developed with assistance from OpenAI Codex.

The display API approach was researched from:

- [LightsOut](https://github.com/AlonX2/LightsOut), copyright 2024 AlonX2, MIT: display transactions and reconnect behavior.
- [displayplacer](https://github.com/jakehilborn/displayplacer), MIT: changing enablement separately from layout and avoiding redundant enablement calls.
- [displayplacer reconnect discussion](https://github.com/jakehilborn/displayplacer/issues/137): explicitly reconnecting a disabled monitor using its previously known display ID.
- [Clamless](https://github.com/TCXM/clamless): API signatures and separate enablement transactions.
- Apple's CoreGraphics and AppKit SDK documentation.

These apps are not bundled dependencies. This repository contains its own controller, backend, menu UI, and tests. The feature is already provided by LightsOut; this project makes no novelty claim.
