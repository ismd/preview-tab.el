# Changelog

Notable changes to preview-tab. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A preview that could not be killed — visible in another window, or running a
  process — stayed flagged as a preview forever. Only one preview is tracked at
  a time, so once the next one took over nothing would ever kill or keep it:
  the buffer sat there italicised and marked for the rest of the session. It now
  becomes an ordinary buffer instead.
- Turning `preview-tab-mode` off did not always stop it. The advice was removed
  by walking the current value of `preview-tab-commands` rather than the list it
  had actually been attached to, so changing that list with plain `setq` left
  advice behind — and the advice never checked whether the mode was on, so it
  went on marking and killing buffers.
- The mode-line marker was installed with `add-to-list`, which edits the
  buffer-local value of `mode-line-misc-info` when the current buffer has one.
  Enabling the global mode from such a buffer put the marker in that buffer and
  nowhere else; disabling from one left the entry behind for good.
- Killing a preview yourself left `preview-tab-buffer` pointing at the dead
  buffer.
- A command that opened a second file on the way — a hook reading something, a
  language server warming up — could hand the preview to that buffer instead of
  the one on screen.
- A command that visited the file and then signalled, or was interrupted with
  `C-g`, left the buffer open and tracked by nobody: never reaped, never
  promoted.
- `called-interactively-p` returned nil inside every advised command, because
  `:around` advice hides `call-interactively` from it.

### Removed

- `consult-line` is no longer in `preview-tab-commands` by default. It searches
  the buffer you are already in and never visits a file, so advising it did
  nothing.

## [0.1.0]

Initial version: `preview-tab-mode`, `preview-tab-find-file` and
`preview-tab-keep`, with the mode-line marker and the italicised buffer path.
