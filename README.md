# preview-tab

[![test](https://github.com/ismd/preview-tab.el/actions/workflows/test.yml/badge.svg)](https://github.com/ismd/preview-tab.el/actions/workflows/test.yml)
[![melpazoid](https://github.com/ismd/preview-tab.el/actions/workflows/melpazoid.yml/badge.svg)](https://github.com/ismd/preview-tab.el/actions/workflows/melpazoid.yml)

VS Code's preview tab, for Emacs.

Browsing a project leaves a trail of buffers behind. Every file you glanced at
from the file tree, every definition you jumped to, every grep hit you opened
sits in the buffer list forever, and `C-x b` slowly turns into an archive of
things you looked at once.

VS Code solves this with the *preview tab*: a file opened by browsing goes into
a single italicised tab, the next such file replaces it, and it only becomes a
real tab once you edit it. `preview-tab-mode` brings that behaviour to Emacs.

```elisp
(preview-tab-mode 1)
```

That's it. Now opening a file from Dired, Treemacs, Magit, `xref`, grep results
or `consult` puts it in one temporary buffer, marked in the mode line. Open the
next one and the previous is gone.

## The rules

A buffer becomes a **preview** when a command in `preview-tab-commands` visits a
file that was not already open.

It stops being a preview — permanently — when you **edit it** (the first change
promotes it) or run **`preview-tab-keep`**.

The preview is killed when the next preview takes its place, *unless* it is
modified, visible in another window, or running a process. Those quietly become
ordinary buffers instead.

Two things deliberately do **not** happen, both matching VS Code:

- A buffer that was already open is never demoted to a preview.
- Visiting an ordinary buffer does not close the standing preview. It survives
  until another preview replaces it, not until you look away.

`find-file` is **not** a preview source: typing a file name is a deliberate act,
and VS Code does not preview from Quick Open either. To peek at a named file,
use `preview-tab-find-file` — or turn the rule off, see
[Previewing `find-file`](#previewing-find-file).

## Commands

| Command | What it does |
| --- | --- |
| `preview-tab-mode` | Turn the whole thing on or off. Turning it off makes every preview permanent. |
| `preview-tab-find-file` | Visit a file as a preview — the "just let me look at it" counterpart to `find-file`. Files already open are left alone. |
| `preview-tab-keep` | Keep the current preview buffer for good. |

Suggested bindings:

```elisp
(global-set-key (kbd "C-c f t") #'preview-tab-find-file)
(global-set-key (kbd "C-c t p") #'preview-tab-keep)
```

## Installation

Not on MELPA yet. No dependencies beyond Emacs 27.1.

```elisp
;; use-package on Emacs 29+
(use-package preview-tab
  :vc (:url "https://github.com/ismd/preview-tab.el" :rev :newest)
  :config (preview-tab-mode 1))

;; straight.el
(use-package preview-tab
  :straight (:host github :repo "ismd/preview-tab.el")
  :config (preview-tab-mode 1))

;; elpaca
(use-package preview-tab
  :ensure (:host github :repo "ismd/preview-tab.el")
  :config (preview-tab-mode 1))
```

### Doom Emacs

Doom's own jump and search commands are not in the default list, so add them:

```elisp
;; packages.el
(package! preview-tab :recipe (:host github :repo "ismd/preview-tab.el"))

;; config.el
(use-package! preview-tab
  :config
  (dolist (cmd '(+default/search-cwd
                 +default/search-project
                 +lookup/definition
                 +lookup/implementations
                 +lookup/references
                 +lookup/type-definition))
    (add-to-list 'preview-tab-commands cmd))
  (preview-tab-mode 1))
```

Then run `doom sync` and restart Emacs.

One more Doom default is worth changing. Out of the box, `consult` shows you the
file under point as you move down the candidate list; Doom turns that off, so
nothing appears until you press `C-SPC` on a candidate. To get the automatic
display back:

```elisp
(after! consult
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep consult-recent-file
   consult-source-recent-file consult-source-project-recent-file
   +default/search-project +default/search-cwd
   :preview-key '(:debounce 0.2 any)))
```

That is consult's own preview, not this package's: it only affects what you see
while still choosing, and consult closes those buffers itself when the session
ends. `preview-tab` is unaffected either way — the file you finally pick becomes
a preview if the command that opened it is in `preview-tab-commands`.

## Customization

| Option | Default | Meaning |
| --- | --- | --- |
| `preview-tab-commands` | Dired, Treemacs, Magit, xref, compile/grep, flymake, consult | Commands whose file visits are previews. |
| `preview-tab-include-find-file` | nil | Whether `find-file` and `magit-find-file` preview too. |
| `preview-tab-slant-faces` | vanilla, doom-modeline, centaur-tabs faces | Faces italicised while a buffer is a preview. `tab-line-mode` is handled separately, by `preview-tab-tab-line-face`. |
| `preview-tab-indicator` | `auto` | `auto`, `icon`, `label`, `both`, or nil. |
| `preview-tab-icon` | `"nf-md-eye_outline"` | [nerd-icons](https://github.com/rainstormstudio/nerd-icons.el) Material Design icon name. |
| `preview-tab-label` | `"PREVIEW"` | Text marker. |

### Magit

`RET` on a file in a Magit status or diff buffer runs `magit-diff-visit-file`,
a preview source out of the box — as are its worktree, other-window and
other-frame variants.

One caveat, and it is Magit's design rather than this package's:
`magit-diff-visit-file` does not always visit a *file*. Which side of the diff
it opens depends on the line point is on — an added or context line gives the
new side, a removed line the old one. For a committed or staged change both
sides are blobs, from a commit or from the index; a blob buffer is read-only,
visits nothing on disk, and is left alone. Untracked files, and unstaged changes
seen from an added or context line, open the real worktree file — as does
`magit-diff-visit-worktree-file` (`C-j`, or `C-<return>`) from anywhere. Those
become previews.

### Previewing `find-file`

Neither `find-file` nor `magit-find-file` is a preview source. If you'd rather
they were:

```elisp
(setopt preview-tab-include-find-file t)
```

`setopt` arrives in Emacs 29. Before that — here and everywhere else this README
reaches for it — `customize-set-variable` does the same job:
`(customize-set-variable 'preview-tab-include-find-file t)`.

In Doom, add `:custom (preview-tab-include-find-file t)` to the `use-package!`
block under [Doom Emacs](#doom-emacs) rather than writing a second one. `:custom`
goes through `customize-set-variable`, which is the machinery this option needs,
and it is applied before `:config`, so the mode comes up already knowing.

That takes in both, along with their other-window and other-frame variants. It
also reaches further than the name suggests: a great deal of Emacs opens files
by calling `find-file`, so `project-find-file`, `recentf-open-files` and file
registers start previewing too. Anything going through `find-file-noselect`
instead is untouched — bookmarks, for one.

I run with this on myself: the wider reach turns out to be the same instinct one
step out, not a surprise in kind.

For `find-file` alone, leave the option off and list it where everything else
goes:

```elisp
(setopt preview-tab-commands (cons #'find-file preview-tab-commands))
```

### Adding your own entry points

Listing a command from a package you have not installed is harmless — the
advice attaches to the bare symbol and only fires if that package loads. Add
things freely, as long as you do it *before* turning the mode on:

```elisp
(add-to-list 'preview-tab-commands #'my-jump-to-thing)
(preview-tab-mode 1)
```

Afterwards `add-to-list` won't reattach the advice. Go through the customize
machinery instead, which will:

```elisp
(setopt preview-tab-commands (cons #'my-jump-to-thing preview-tab-commands))
```

One limit: only files opened while the command itself runs are picked up. A
command that hands the visit off to a timer or `post-command-hook` has already
returned by the time the file appears.

### The mode-line marker

The preview buffer's path is italicised and a small marker is shown: an eye icon
with `nerd-icons` installed, otherwise the text `PREVIEW`. Set
`preview-tab-indicator` to `both` for icon *and* label, or to nil for italics
only — closest to what VS Code actually does. If your mode line isn't italicised,
add its faces to `preview-tab-slant-faces`.

Under `tab-line-mode` the preview's tab is italicised as well, and stays that
way when you select another tab — the VS Code look. This is done by
`preview-tab-tab-line-face`, which the mode adds to
`tab-line-tab-face-functions`, and it needs Emacs 28.1, where that hook
arrived. On Emacs 27 the tabs are not slanted; the mode-line marker is
unaffected.

## Relationship to consult

`consult` kills the buffers it opens while you scroll through candidates.
`preview-tab` picks up at the file you actually *chose*, which consult keeps.

## Development

```sh
make compile    # byte-compile, warnings are errors
make lint       # package-lint + checkdoc
make test       # behavioural suite
make test-tty   # frame-dependent suite
make all
```

The suite is split in two because `emacs --batch` has no frame, and
`format-mode-line` returns the empty string for *every* input there. Mode-line
tests therefore run on a terminal frame under a pty via util-linux `script(1)`
(BSD and macOS ship a different program under that name; the target checks up
front). To exercise the icon tests, point `make` at a `nerd-icons` checkout:

```sh
make test-tty NERD_ICONS=~/.emacs.d/elpa/nerd-icons
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
