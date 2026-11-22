# Changelog

## Unreleased

- Index output paths and manifest ownership so large builds avoid comparing every file with every other file.

## 1.1.0

- Use stdlib 0.4.1 console output in the CLI and live watcher.

- Highlight error and warning labels, source gutters, help, compiler activity, and echo locations in terminal and plain text fences.

## 1.0.0

- Serve base-path deployments beneath their configured URL prefix, with segment-boundary matching, single decoding and watched retargeting.

- Recognise portable file-tree fences, preserving indentation and colouring directories while escaping filenames and notes.

- Refresh existing CSS assets in place during preview, with full reloads for structural edits, missed events and stylesheet failures.
- Preserve feed and entry identifiers when moving existing sites, with explicit feed titles/descriptions and build-clock Atom updates.

- Generate the full starter source tree, navigation data and an editable theme stylesheet; create publication/cache directories only when used.

- Add Atom/RSS feeds, sitemap, robots and JSON search exports to staged publication.
- Render GFM extensions, duplicate-aware heading anchors/outlines, escaped build-time highlighting and coloured terminal snapshots.
- Add URL, date, collection, asset-fingerprint, reading-time and restricted sample helpers.
- Capture one build clock and expose development/production context; local serving always stays in development.
- Add explicitly registered Pooka data providers, bounded verified HTTP fetching and versioned expiring provider caches.
- Validate rendered local links and anchors with `check`; include samples in watched inputs.
- Give CLI init a linked example post and feed; add terminal-aware orange summaries, human-readable durations and `--no-color`.
- Add cache cleanup and source-aware metadata/configuration diagnostics.

- Start Jinks with site `config.toml` and theme `theme.toml`.
- Add init, check, build, and individual command help.
- Render Markdown/TOML pages through Tuck themes and site overrides.
- Expose nested site/page parameters with escaped metadata.
- Copy static assets without changing bytes and honour site overrides.
- Reject colliding routes/assets, unsafe relative settings, and source/output overlap.
- Add local generated-site tests and website migration inventories.
- Publish through staging with rename/rollback and a versioned owned-file manifest.
- Remove stale generated files while preserving unowned output.
- Add clean, exclusive writer locking, source/output symlink checks, and failure recovery tests.
- Add a loopback HTTP preview server with GET/HEAD, directory indexes, MIME types, binary assets, and custom 404s.
- Add serve TOML settings, CLI host/port overrides, and browser reload control.
- Watch input hashes, debounce saves, serialize staged rebuilds, and retarget changed output directories.
- Stream reload events and persistent rebuild errors to a development-only browser client.
- Add real HTTP integration tests, watcher recovery tests, and a three-platform CI workflow.
- Stamp served HTML with its build revision to catch edits during the first event-stream connection.
- Enforce LF checkouts as a workaround for the released compiler’s CRLF lockfile limitation.
- Add typed collections with nearest-directory membership, cached deterministic sorting, page defaults, and previous/next summaries.
- Support validated publication days, explicit permalinks, slug overrides, and draft/future filtering.
- Merge nested theme/site parameters and load local TOML/JSON data into templates.
- Encode public URLs correctly and preserve front matter source diagnostics.
- Add content/data documentation, regression tests, and a collection HTML snapshot.
- Render standalone Tuck content with optional layouts, shared theme inheritance/includes, and output-based escaping.
- Generate collision-checked static alias redirects and remove stale aliases through the manifest.
- Preserve content-file/front-matter locations and partial locations in template diagnostics.
- Add config/output/base-URL/visibility overrides across build, check, and serve; retain choices through watched rebuilds.
- Support config/output selection in safe clean and consistent command help without requiring a site.
- Add standalone/alias snapshots and configuration-relative path, output-format, and CLI regression tests.
- Add opt-in collection archives, Unicode tag groups, paginated tag indexes, and bounded pagination links.
- Cache tag membership and neighbouring-page lookups; preflight generated routes before rendering.
- Extend the minimal theme with listing layouts, accessible pagination, and system light/dark colours.
- Test generated listings during live reload and remove stale generated routes safely.
- Use an Intel macOS CI runner after hosted ARM capacity prevented job acquisition.
- Add `new` for Markdown drafts with title/date/layout options, selected configuration, inherited defaults, and exclusive source creation.
- Reject unsafe, linked, existing, and case/Unicode-aliased authoring paths; cover metadata escaping and draft visibility.
