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

That's it. Now opening a file from Dired, Treemacs, `xref`, grep results or
`consult` puts it in one temporary buffer, marked in the mode line. Open the
next one and the previous is gone.

## The rules

A buffer becomes a **preview** when a command in `preview-tab-commands` visits a
file that was not already open.

It stops being a preview — permanently — when you:

- **edit it** (the first change promotes it), or
- run **`preview-tab-keep`**.

The preview is killed when the next preview takes its place, *unless* it is
modified, visible in another window, or running a process. Those are never
killed — they quietly become ordinary buffers instead. Only one preview is
tracked at a time, so a buffer nothing will ever come back for must not be
left pretending to be one.

Two things deliberately do **not** happen, both matching VS Code:

- A buffer that was already open is never demoted to a preview. Browsing to it
  leaves it alone.
- Visiting an ordinary buffer does not close the standing preview. The preview
  survives until another preview replaces it, not until you look away.

`find-file` is **not** a preview source. Typing a file name is a deliberate act,
and VS Code does not preview from Quick Open either. When you do want to just
peek at a named file, use `preview-tab-find-file` — though if the file is
already open it stays as it is, since nothing here demotes a buffer you
already have.

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

Not on MELPA yet. With `use-package` on Emacs 29+:

```elisp
(use-package preview-tab
  :vc (:url "https://github.com/ismd/preview-tab.el" :rev :newest)
  :config (preview-tab-mode 1))
```

With [straight.el](https://github.com/radian-software/straight.el):

```elisp
(use-package preview-tab
  :straight (:host github :repo "ismd/preview-tab.el")
  :config (preview-tab-mode 1))
```

With [elpaca](https://github.com/progfolio/elpaca):

```elisp
(use-package preview-tab
  :ensure (:host github :repo "ismd/preview-tab.el")
  :config (preview-tab-mode 1))
```

There are no dependencies beyond Emacs 27.1.

## Customization

| Option | Default | Meaning |
| --- | --- | --- |
| `preview-tab-commands` | Dired, Treemacs, xref, compile/grep, flymake, consult | Commands whose file visits are previews. |
| `preview-tab-slant-faces` | vanilla, doom-modeline, tab-line, centaur-tabs faces | Faces italicised while a buffer is a preview. |
| `preview-tab-indicator` | `auto` | `auto`, `icon`, `label`, `both`, or nil. |
| `preview-tab-icon` | `"nf-md-eye_outline"` | [nerd-icons](https://github.com/rainstormstudio/nerd-icons.el) Material Design icon name. |
| `preview-tab-label` | `"PREVIEW"` | Text marker. |

### Adding your own entry points

Listing a command from a package you have not installed is harmless — the
advice attaches to the bare symbol and only ever fires if that package loads.
So you can add things freely — as long as you do it before turning the mode
on:

```elisp
(add-to-list 'preview-tab-commands #'my-jump-to-thing)
(preview-tab-mode 1)
```

Afterwards the advice is already attached to whatever the list held at the
time, and `add-to-list` won't reattach it. Go through the customize machinery
instead, which will:

```elisp
(setopt preview-tab-commands (cons #'my-jump-to-thing preview-tab-commands))

;; before Emacs 29:
(customize-set-variable 'preview-tab-commands
                        (cons #'my-jump-to-thing preview-tab-commands))
```

One limit worth knowing: only files opened while the command itself runs are
picked up. A command that hands the visit off to a timer, a process filter or
`post-command-hook` has already returned by the time the file appears, and its
buffer stays an ordinary one.

### The mode-line marker

The preview buffer's path is italicised and a small marker is shown. With
`nerd-icons` installed you get an eye icon; without it, the text `PREVIEW`.
Set `preview-tab-indicator` to `both` for the icon *and* the label, or to nil to
keep only the italics — closest to what VS Code actually does.

The italics work by remapping `preview-tab-slant-faces`. The default list covers
several mode lines at once on purpose: remapping a face the current mode line
never draws, or that is not even defined, costs nothing and fails silently, so
there is no need to detect which mode line you use. If yours is not covered, add
its faces to the list.

## Doom Emacs

```elisp
;; packages.el
(package! preview-tab :recipe (:host github :repo "ismd/preview-tab.el"))

;; config.el
(use-package! preview-tab
  :custom
  (preview-tab-icon "nf-md-eye_outline")
  :config
  (dolist (cmd '(+lookup/definition +lookup/references +lookup/implementations
                 +lookup/type-definition
                 +default/search-project +default/search-cwd))
    (add-to-list 'preview-tab-commands cmd))
  (preview-tab-mode 1))

(map! :prefix "C-c f" :desc "Find file (preview)" "t" #'preview-tab-find-file)
(map! :prefix "C-c t" :desc "Keep preview buffer" "p" #'preview-tab-keep)
```

Note that Doom hides `consult` previews behind `C-SPC`. If you want browsing
search results to show the file immediately — the same instinct this package
serves — restore consult's own default:

```elisp
(after! consult
  (consult-customize
   consult-ripgrep consult-git-grep consult-grep consult-recent-file
   consult-source-recent-file consult-source-project-recent-file
   +default/search-project +default/search-cwd
   :preview-key '(:debounce 0.2 any)))
```

## Relationship to consult

`consult` already cleans up after itself: buffers it opens while you scroll
through candidates are killed when you leave the minibuffer. `preview-tab` picks
up where that stops — at the file you actually *chose*, which consult keeps.

## Development

```sh
make compile    # byte-compile, warnings are errors
make lint       # package-lint + checkdoc
make test       # behavioural suite
make test-tty   # frame-dependent suite
make all
```

The suite is split in two, and this is not stylistic. Under `emacs --batch`
there is no frame, and `format-mode-line` returns the empty string for *every*
input — a batch test asserting on rendered mode-line text passes or fails for
reasons unrelated to the code. Those tests run on a terminal frame under a pty
instead, via `script(1)`. `preview-tab-tty-test-frame-can-render-a-mode-line`
guards the file: it fails under `--batch`, proving the suite is not vacuous.

`make test-tty` wants the util-linux `script`. BSD and macOS ship a different
program under that name, taking different arguments; the target checks for it
up front and says so rather than failing obscurely halfway through.

To exercise the icon tests, point `make` at a `nerd-icons` checkout:

```sh
make test-tty NERD_ICONS=~/.emacs.d/elpa/nerd-icons
```

## Prior art

Nothing in MELPA, GNU ELPA or NonGNU ELPA does this. The closest is
[`rscope.el`](https://github.com/rjarzmik/rscope), which keeps a list of preview
buffers, but only for cscope result browsing.
[`dired-preview`](https://protesilaos.com/emacs/dired-preview) previews files in
a side window from Dired, and
[`buffer-terminator`](https://github.com/jamescherti/buffer-terminator.el) kills
buffers by inactivity — both solve neighbouring problems, neither is a preview
tab. The [treemacs request for this](https://github.com/Alexander-Miller/treemacs/issues/527)
was closed without an implementation.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
