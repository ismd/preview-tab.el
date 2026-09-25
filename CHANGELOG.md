# Changelog

Notable changes to preview-tab. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0]

### Added

- `preview-tab-include-named-files` now takes in `org-roam-node-find`. Picking
  a note by title is naming it, so it belongs with `find-file` rather than in
  the default list. It has to be named outright: it visits the note with
  `find-file-noselect`, so turning the option on used to leave it untouched.

### Changed

- `preview-tab-include-find-file` is now `preview-tab-include-named-files`.
  The name had stopped describing the option once `magit-find-file`,
  `+lookup/file` and `org-roam-node-find` came along, the last of which never
  calls `find-file` at all. No alias is kept for the old name.

### Fixed

- A file the command has already written into is no longer made a preview.
  Editing is what promotes a preview, but `first-change-hook` does not hear of
  an edit made before the buffer was marked, nor of one made through an
  indirect buffer — which is how Org capture writes a new note, and so what
  `org-roam-node-find` does for a title with no note behind it. Such a buffer
  used to be marked anyway, and was killed by the next preview as soon as it
  had been saved.

## [0.5.0]

### Changed

- A `preview-tab-icon` that `nerd-icons` has no icon for is now looked up and
  reported rather than drawn and caught. `nerd-icons-mdicon` signals on a name
  it does not know, and the marker is built inside redisplay, so the call used
  to be wrapped in `ignore-errors` — which also swallowed the one thing worth
  saying, that the option is misconfigured. The name is now checked against
  `nerd-icons`' own table before it is drawn, so nothing can signal, and a name
  that is not in it is reported once in `*Warnings*`, from a timer that lands
  the report in the command loop rather than in redisplay. A `nerd-icons` still
  behind an autoload — what `use-package` `:commands` leaves — is loaded first,
  as calling the icon function used to do by accident: a table that is not
  there yet is no verdict on the name, and neither the verdict nor the marker
  it decides is cached until it is. The verdict is then cached like any other,
  instead of rescanning several thousand entries on every redisplay.

### Removed

- The `declare-function` forms for `nerd-icons-mdicon` and
  `tab-line-force-update`. Both calls are gated on `fboundp`, which already
  tells the byte-compiler what the declarations did, and a declaration left
  standing goes on covering for whatever real mistake comes along next.

## [0.4.0]

### Added

- Doom Emacs jumps and searches are preview sources out of the box:
  `+lookup/definition`, `+lookup/implementations`, `+lookup/references`,
  `+lookup/type-definition`, the `+default/search-*` family, and the
  `+vertico/`, `+ivy/` and `+helm/` project searches those dispatch to. Doom
  users no longer need to splice them into `preview-tab-commands` by hand —
  which was also the one mutation pattern the option warns against, since
  `add-to-list` does not reattach the advice.
- `preview-tab-include-find-file` now takes in Doom's `+lookup/file` as well.
  It resolves a path at point and falls back to `find-file-at-point`, so it
  belongs with `find-file` rather than in the default list.

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
