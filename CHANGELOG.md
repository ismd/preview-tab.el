# Changelog

Notable changes to preview-tab. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0]

### Added

- `preview-tab-tab-line-face`, added to `tab-line-tab-face-functions` while the
  mode is on. It is public because Customize will offer it to anyone who edits
  that option, and saving from there writes the name to their custom file.

### Fixed

- Under `tab-line-mode`, the preview's tab lost its italics as soon as another
  tab was selected. The slant came from a buffer-local face remapping, which
  only reaches a tab line drawn for the preview buffer itself — never one drawn
  by the window showing whatever you switched to. The tab is now slanted through
  `tab-line-tab-face-functions`, so it stays italic in every window, and
  tab-line's render cache is cleared whenever a buffer takes on or gives up
  preview status. Needs Emacs 28.1, where that hook arrived; on Emacs 27 tabs
  are not slanted at all, and the mode-line marker is unaffected.

### Changed

- `tab-line-tab-current` is no longer in the default `preview-tab-slant-faces`.
  Remapping it only ever slanted the tab while the preview was the selected
  buffer, which is the bug above; `preview-tab-tab-line-face` covers the tab
  line properly now. Nothing else in the list changed.

## [0.2.0]

### Added

- `preview-tab-include-find-file`, off by default, makes `find-file` and
  `magit-find-file` preview too — each along with the variant that opens in
  another window and the one that opens in another frame. Note that much of
  Emacs opens files by calling `find-file` itself, so `project-find-file` and
  `recentf-open-files` start previewing along with it.
- Magit is a preview source. `RET` on a file in a Magit status or diff buffer —
  `magit-diff-visit-file`, along with its worktree, other-window and
  other-frame variants — now opens into the preview buffer. Note that Magit
  visits the index or a commit's blob rather than the file itself for staged
  and committed changes; those buffers are not file buffers and are left alone.

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
