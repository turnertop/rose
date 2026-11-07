# Publication preparation

Rose is being prepared for a first public source release under Apache-2.0.
The owner selected the unchanged Apache License 2.0 in `LICENSE`, with project
attribution in `NOTICE`. No publication is authorized by this document or by
the license selection itself.

## Keep private history separate

The development repository retains the full pre-publication history. A cleanup
commit does not remove older file contents. Preserve that repository and its
stable tags locally, then export the reviewed source into a separate directory
with a new Git history. The public starting commit must have no parent commits,
old branches, old tags, copied `.git` directory, or local Git configuration.

The snapshot should contain both the Swift application at the root and the
Windows implementation under `desktop/`. Generated builds, image libraries,
sidecars, local app state, diagnostics, and credentials must be absent. Keep
third-party notices and label supplied design illustrations as concepts.

## Prevent accidental publication

`AGENTS.md` requires explicit owner approval of the destination and contents
before a remote is configured or anything is uploaded. Local commits and local
release packages are permitted preparation work; they are not publication.

Install the fail-closed hook in each local preparation checkout:

```sh
bash scripts/install-push-guard.sh
```

The installer copies the tracked template into a private Git directory and
configures the hook locally. Switching branches cannot remove the active guard.
The installer refuses to overwrite an unrelated custom hooks configuration.
Hooks and local Git configuration are not installed automatically by a clone;
run the installer in each new checkout used for preparation.

Check the local boundary with:

```sh
git remote -v
git config --local --get core.hooksPath
```

Preparation checkouts should have no remotes. The hook blocks ordinary pushes,
including pushes to an explicitly supplied URL, but it can be bypassed or
removed and does not control direct API uploads. Do not treat it as a security
sandbox. Stronger separation means withholding GitHub write credentials and
write-capable account tools from the preparation environment, and publishing
from a separate environment only after review. Repository instructions alone
cannot guarantee what a future agent with unrestricted access will do.

## Release gate

Before the owner approves publication:

1. Include the standard Apache-2.0 `LICENSE` and project `NOTICE` in the source
   and distributable packages. The macOS and Windows packaging scripts copy
   both files. Preserve dependency licenses and attribution separately; they
   continue to apply to their own components. Any future project manifesto
   should be reviewed separately; none has been added during preparation.
2. Review all tracked files and reachable history in the clean snapshot for
   credentials, identifying paths, personal images/state, and private notes.
   Confirm that Git author/committer metadata is intentionally public.
3. Run the Swift checks and desktop checks from that snapshot, and build release
   packages from its clean commit. Do not copy a binary whose source provenance
   refers only to private development history.
4. Inspect source archives and binary packages, including manifests, symbols,
   notices, metadata, checksums, and install/run instructions. Keep source-only
   ZIPs clearly distinct from runnable app downloads.
5. Record the actual validation limits. The Windows build is a preview; native
   Windows integration, accessibility, and large-library performance still need
   further acceptance checks. Linux is not a validated release.
6. Obtain explicit owner approval of the reviewed source, release assets, and
   GitHub destination. Only then configure the publication workflow, change the
   local push guard intentionally, and create the public release.

For easier downloads, publish versioned app ZIPs and SHA-256 files as release
assets. A public source release and any binary distribution must carry the
chosen project license and required dependency notices.
