# Working on Rose

## Publication boundary

- Editing, testing, packaging, and creating local commits do not authorize
  publication. Keep this work local unless the owner explicitly approves the
  destination and contents in the current task.
- Do not create remote repositories, add or change remotes, push branches or
  tags, mirror this repository, publish releases, or upload source/builds to an
  external service without that approval. This includes direct API uploads.
- The development repository retains pre-publication history. It must not be
  pushed or mirrored wholesale. Use a reviewed clean snapshot for the first
  public release; do not copy old refs, reflogs, or Git configuration into it.
- The owner selected Apache-2.0. Keep the standard `LICENSE` text and project
  `NOTICE` with distributions; preserve third-party licenses and notices.
  Licensing does not authorize publication. Do not change the license or add
  manifesto text without a separate owner request.
- `.githooks/pre-push` is the fail-closed template. Run
  `bash scripts/install-push-guard.sh` to install it in the repository's private
  Git directory so it survives branch switches. Keep `core.hooksPath` pointing
  to that installed guard; do not bypass it as part of routine work. Hooks and
  these instructions are safeguards against mistakes, not an access-control
  boundary.
- Before any approved publication, review the exact source, reachable history,
  release contents, licenses, and generated metadata. See `docs/Publishing.md`.

## Development

- The repository root is the native Swift macOS app. `desktop/` is the separate
  C# / Avalonia Windows implementation. Keep both in this repository.
- Use `codex/` branches for changes. Preserve existing stable tags and history.
- Never commit actual image libraries, annotations, saved indexes/bookmarks,
  thumbnails, credentials, or machine-specific diagnostics. Use generated
  fixtures and ignored local data directories.
- Run `./scripts/check.sh` for Swift changes and `bash scripts/check.sh` from
  `desktop/` for desktop changes. Tests use temporary data; never point them at
  a personal image library.
- Do not launch a native app, computer-use connection, or screen-capture session
  for this preparation task. Use existing offscreen/headless checks. GUI checks
  require a separate explicit request.
