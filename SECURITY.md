# Security policy

`cfence` is a guard rail for one human on one machine, not a sandbox. Reports that the **fence can be bypassed silently** (the wrong account launching without a refusal), credentials/secrets being exposed (file modes, logs), or arbitrary file writes via crafted names/paths are in scope.

Please report privately via GitHub's *Security → Report a vulnerability* (or the maintainer's email) rather than a public issue. Include a minimal reproduction in a throwaway `$HOME`. You'll get an acknowledgement within a few days.
