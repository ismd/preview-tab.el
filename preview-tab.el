;;; preview-tab.el --- Temporary file buffers, like VS Code's preview tab  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Vladimir Kosteley

;; Author: Vladimir Kosteley <github@ismd.dev>
;; Version: 0.1.0
;; URL: https://github.com/ismd/preview-tab.el
;; Keywords: convenience, files
;; Package-Requires: ((emacs "27.1"))
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Browsing a project in Emacs leaves a trail of buffers behind.  Every file you
;; glanced at from the file tree, every definition you jumped to, every grep hit
;; you opened stays in the buffer list forever.
;;
;; VS Code solves this with the preview tab: a file opened by browsing goes into
;; a single italicised tab, the next such file replaces it, and the tab only
;; becomes permanent once you edit it.  `preview-tab-mode' brings that to Emacs.
;;
;; Enable it and the commands in `preview-tab-commands' -- file managers, xref,
;; grep, consult and friends -- open files into one temporary buffer:
;;
;;     (preview-tab-mode 1)
;;
;; The preview buffer is killed when the next preview replaces it, and it turns
;; into an ordinary buffer as soon as you edit it or run `preview-tab-keep'.
;; A buffer that was already open is never demoted to a preview, and a preview
;; that is modified, visible in another window, or running a process is never
;; killed -- it becomes an ordinary buffer instead.
;;
;; Two commands are provided beyond the mode itself:
;;
;;   `preview-tab-find-file'  visit a file as a preview instead of for good --
;;                            the deliberate "just let me look at it"
;;                            counterpart to `find-file'
;;   `preview-tab-keep'       keep the current preview buffer for good
;;
;; Typing a file name is taken as a deliberate act and opens the file for good,
;; as in VS Code.  Set `preview-tab-include-find-file' if you would rather
;; `find-file' previewed too.
;;
;; The current preview is marked in the mode line: the buffer path is italicised
;; and a small indicator is shown.  Both are configurable; see
;; `preview-tab-slant-faces' and `preview-tab-indicator'.

;;; Code:

(require 'face-remap)
(require 'seq)

(declare-function nerd-icons-mdicon "nerd-icons" (icon-name &rest args))


;;;; State

(defvar preview-tab-buffer nil
  "The buffer currently held open as a preview, or nil.")

(defvar-local preview-tab--previewing nil
  "Non-nil when this buffer is the preview buffer.")

(defvar-local preview-tab--face-cookies nil
  "Cookies from `face-remap-add-relative' slanting the mode line.")

(defvar preview-tab--busy nil
  "Non-nil while a command from `preview-tab-commands' is on the stack.
Keeps the outermost command in charge when they nest, as when
`compile-goto-error' calls `next-error'.")

(defvar preview-tab--advised nil
  "Commands `preview-tab-mode' actually advised when it was turned on.
Turning the mode off has to undo exactly what turning it on did, and reading
`preview-tab-commands' a second time would not: nothing stops it from having
changed in between, and any command dropped from it would keep the advice for
the rest of the session.")

(defvar preview-tab--indicator-cache nil
  "Rendered mode-line marker.
`nerd-icons' resolves a name by scanning an alist of several thousand
entries, which is far too slow to redo on every redisplay.")

(defvar preview-tab--mode-line-entry
  '(preview-tab--previewing (:eval (preview-tab--indicator)))
  "Construct `preview-tab-mode' adds to `mode-line-misc-info'.
`mode-line-misc-info' is part of the default `mode-line-format' and of
doom-modeline's `main' mode line, so this shows up either way.")


;;;; Customization

(defgroup preview-tab nil
  "Temporary file buffers, in the spirit of VS Code's preview tab."
  :group 'convenience
  :prefix "preview-tab-"
  :link '(url-link "https://github.com/ismd/preview-tab.el"))

(defvar preview-tab-mode)

(defun preview-tab--set-and-refresh (symbol value)
  "Set SYMBOL to VALUE, restarting `preview-tab-mode' if it is on.
Used as a `defcustom' setter for options that are only read when the mode is
turned on.  `bound-and-true-p' matters here: `defcustom' runs its setter while
the file is still loading, before `define-minor-mode' has defined the
variable."
  (set-default symbol value)
  (when (bound-and-true-p preview-tab-mode)
    (preview-tab-mode -1)
    (preview-tab-mode 1)))

(defun preview-tab--set-indicator (symbol value)
  "Set SYMBOL to VALUE and invalidate the cached mode-line marker."
  (set-default symbol value)
  (setq preview-tab--indicator-cache nil))

(defcustom preview-tab-commands
  '(;; file managers
    dired-find-file
    dired-find-alternate-file
    dired-find-file-other-window
    treemacs-visit-node-no-split
    treemacs-visit-node-in-most-recently-used-window
    ;; version control
    magit-diff-visit-file
    magit-diff-visit-file-other-window
    magit-diff-visit-file-other-frame
    magit-diff-visit-worktree-file
    magit-diff-visit-worktree-file-other-window
    magit-diff-visit-worktree-file-other-frame
    ;; code navigation
    xref-goto-xref
    xref-find-definitions
    xref-find-references
    ;; search results and diagnostics
    compile-goto-error
    next-error
    previous-error
    first-error
    flymake-goto-diagnostic
    consult-ripgrep
    consult-grep
    consult-git-grep
    consult-flymake)
  "Commands whose file visits are treated as temporary previews.

Commands from packages that are not installed are harmless: advice attaches
to the bare symbol and takes effect if the package is ever loaded.  This is
why third-party commands can be listed here by default.

Only files opened while the command itself runs are picked up.  A command
that hands the visit off to a timer, a process filter or `post-command-hook'
has already returned by the time the file appears, and its buffer stays an
ordinary one.

Changing this list while the mode is on only takes effect through the
customize machinery -- `setopt', `customize-set-variable', the Customize
interface -- because that is what reattaches the advice.  A plain `setq'
or `add-to-list' will not.

Note that `find-file' is deliberately absent.  Like VS Code, which does not
preview from Quick Open either, typing a file name is taken as a deliberate
act; use `preview-tab-find-file' when you want the other behaviour once, or
`preview-tab-include-find-file' when you want it always."
  :type '(repeat function)
  :set #'preview-tab--set-and-refresh
  :group 'preview-tab)

(defconst preview-tab--find-file-commands
  '(find-file
    find-file-other-window
    find-file-other-frame
    magit-find-file
    magit-find-file-other-window
    magit-find-file-other-frame)
  "Commands `preview-tab-include-find-file' takes in when it is on.")

(defcustom preview-tab-include-find-file nil
  "Whether `find-file' opens a preview too.

Off by default, because naming a file is a deliberate act -- see
`preview-tab-commands'.  Turn it on and `find-file' and `magit-find-file'
preview, each along with the variant that opens in another window and the
one that opens in another frame.

These are advised alongside `preview-tab-commands', so everything said
there applies here too -- including that changing this while the mode is
on only takes effect through the customize machinery.

Turning this on reaches further than the name suggests.  Much of Emacs
opens files by calling `find-file' itself, so `project-find-file',
`recentf-open-files' and jumping to a file register start previewing as
well.  That is the same instinct one step out, but it is worth knowing
before you switch it on.

`magit-find-file' previews only the worktree version of a file.  Asked
for a revision it builds a read-only blob buffer, which visits no file on
disk and is left alone, exactly as in a Magit diff.  If you want
`find-file' without it, leave this off and put `find-file' in
`preview-tab-commands' instead."
  :type 'boolean
  :set #'preview-tab--set-and-refresh
  :group 'preview-tab)

(defcustom preview-tab-slant-faces
  '(;; vanilla Emacs
    mode-line-buffer-id
    ;; doom-modeline splits the path across all of these, and which ones it
    ;; uses depends on `doom-modeline-buffer-file-name-style'
    doom-modeline-project-parent-dir
    doom-modeline-project-dir
    doom-modeline-project-root-dir
    doom-modeline-buffer-path
    doom-modeline-buffer-file
    ;; tab-line-mode
    tab-line-tab-current
    ;; centaur-tabs
    centaur-tabs-selected
    centaur-tabs-selected-modified)
  "Faces italicised in a buffer while it is a preview.

The list covers several mode lines at once on purpose.  Remapping a face
that the current mode line never draws, or that is not even defined, costs
nothing and fails silently, so there is no need to detect which mode line
is in use."
  :type '(repeat face)
  :set #'preview-tab--set-and-refresh
  :group 'preview-tab)

(defcustom preview-tab-indicator 'auto
  "What to show in the mode line for a preview buffer.

`auto'   the icon when `nerd-icons' is available, the label otherwise
`icon'   the icon only, nothing if `nerd-icons' is missing
`label'  the text label only
`both'   the icon followed by the label
nil      no marker; the italicised path is the only cue"
  :type '(choice (const :tag "Icon if available, else label" auto)
                 (const :tag "Icon only" icon)
                 (const :tag "Label only" label)
                 (const :tag "Icon and label" both)
                 (const :tag "No marker" nil))
  :set #'preview-tab--set-indicator
  :group 'preview-tab)

(defcustom preview-tab-icon "nf-md-eye_outline"
  "Name of the `nerd-icons' Material Design icon marking a preview buffer.
Used when `preview-tab-indicator' asks for an icon.  The `nerd-icons'
package is optional; without it the label is shown instead."
  :type 'string
  :set #'preview-tab--set-indicator
  :group 'preview-tab)

(defcustom preview-tab-label "PREVIEW"
  "Text marking a preview buffer in the mode line.
Used when `preview-tab-indicator' asks for a label."
  :type 'string
  :set #'preview-tab--set-indicator
  :group 'preview-tab)

(defface preview-tab-indicator
  '((t (:inherit (mode-line-buffer-id italic) :weight normal)))
  "Face for the preview marker's text label in the mode line."
  :group 'preview-tab)

(defun preview-tab--commands-to-advise ()
  "Return every command the mode should take over.
`preview-tab-commands', and the `find-file' family as well when
`preview-tab-include-find-file' is on.  `seq-uniq' rather than
`delete-dups': a command named in both must be advised once, and the
result has to be a fresh list -- the destructive one would splice a cons
out of the caller's own list, or out of the constant behind the option."
  (seq-uniq (append preview-tab-commands
                    (and preview-tab-include-find-file
                         preview-tab--find-file-commands))))


;;;; The mode-line marker

(defun preview-tab--indicator ()
  "Return the mode-line marker for a preview buffer."
  (or preview-tab--indicator-cache
      (let* ((want-icon (and (memq preview-tab-indicator '(auto icon both))
                             preview-tab-icon))
             (icon (and want-icon
                        (fboundp 'nerd-icons-mdicon)
                        ;; nerd-icons signals on an unknown name, and this runs
                        ;; inside redisplay, where an error is very unwelcome.
                        (ignore-errors (nerd-icons-mdicon preview-tab-icon))))
             (label (and preview-tab-label
                         (or (memq preview-tab-indicator '(label both))
                             (and (eq preview-tab-indicator 'auto) (not icon)))
                         (propertize preview-tab-label
                                     'face 'preview-tab-indicator)))
             (marker (cond ((and icon label) (concat " " icon " " label))
                           (icon (concat " " icon))
                           (label (concat " " label))
                           (t ""))))
        ;; Don't cache a missing icon: `nerd-icons' may just not be loaded yet.
        (when (or icon (not want-icon))
          (setq preview-tab--indicator-cache marker))
        marker)))


;;;; Preview bookkeeping

(defun preview-tab-buffer-p (&optional buffer)
  "Return non-nil if BUFFER is the preview buffer.
BUFFER defaults to the current buffer."
  (buffer-local-value 'preview-tab--previewing (or buffer (current-buffer))))

(defun preview-tab--promote (&optional buffer)
  "Turn BUFFER into an ordinary, permanent buffer.
BUFFER defaults to the current buffer.  Also used as a buffer-local
`first-change-hook', which is why the argument is optional."
  (with-current-buffer (or buffer (current-buffer))
    (when preview-tab--previewing
      (setq preview-tab--previewing nil)
      (remove-hook 'first-change-hook #'preview-tab--promote t)
      (remove-hook 'kill-buffer-hook #'preview-tab--forget t)
      (mapc #'face-remap-remove-relative preview-tab--face-cookies)
      (setq preview-tab--face-cookies nil)
      (force-mode-line-update))
    (when (eq (current-buffer) preview-tab-buffer)
      (setq preview-tab-buffer nil))))

(defun preview-tab--forget ()
  "Forget the current buffer as it is killed.
Buffer-local `kill-buffer-hook'.  A preview killed from outside this package
-- `C-x k', `kill-some-buffers', a mode tidying up after itself -- would
otherwise leave a dead buffer pinned in `preview-tab-buffer'."
  (when (eq (current-buffer) preview-tab-buffer)
    (setq preview-tab-buffer nil)))

(defun preview-tab--disposable-p (buffer)
  "Return non-nil if BUFFER is a preview that may be killed."
  (and (buffer-live-p buffer)
       (buffer-local-value 'preview-tab--previewing buffer)
       (not (buffer-modified-p buffer))
       (not (get-buffer-window buffer t))
       (not (get-buffer-process buffer))))

(defun preview-tab--retire (buffer)
  "Kill BUFFER if it is a disposable preview, otherwise keep it for good.
A preview that survives -- visible elsewhere, modified, or running a
process -- must not stay marked as one.  Only one preview is tracked at a
time, so once the next one takes over nothing would ever come back for
this buffer: it would sit there italicised and flagged forever, never
killed and never kept."
  (when (buffer-live-p buffer)
    ;; The global `kill-buffer-query-functions' are suppressed on purpose: this
    ;; runs from a timer, where a prompt would come out of nowhere, and their
    ;; usual grounds for objecting -- a live process, unsaved changes -- are
    ;; already covered above.  A buffer-local one is out of reach of the
    ;; binding, though, so `kill-buffer' can still turn the kill down after we
    ;; have decided to go ahead.  Whatever the reason, a buffer that survives
    ;; must not be left flagged.
    (unless (and (preview-tab--disposable-p buffer)
                 (let ((kill-buffer-query-functions nil))
                   (kill-buffer buffer)))
      (preview-tab--promote buffer))))

(defun preview-tab--mark (buffer)
  "Make BUFFER the preview buffer, retiring the previous one."
  (let ((old preview-tab-buffer))
    (setq preview-tab-buffer buffer)
    (with-current-buffer buffer
      (unless preview-tab--previewing
        (setq preview-tab--previewing t)
        (add-hook 'first-change-hook #'preview-tab--promote nil t)
        (add-hook 'kill-buffer-hook #'preview-tab--forget nil t)
        (setq preview-tab--face-cookies
              (mapcar (lambda (face) (face-remap-add-relative face 'italic))
                      preview-tab-slant-faces)))
      (force-mode-line-update))
    (when (and old (not (eq old buffer)))
      ;; The old preview is still on screen right now; let redisplay swap it out
      ;; before deciding what to do with it.
      (run-at-time 0 nil #'preview-tab--retire old))))

(defun preview-tab--adopt (known)
  "Make the preview out of whatever file has been visited since KNOWN.
KNOWN is the `buffer-list' from before the command ran."
  (let* ((new (seq-filter (lambda (buf)
                            (and (buffer-file-name buf)
                                 (not (memq buf known))))
                          (buffer-list)))
         ;; A command may open more than one file -- a hook reading something,
         ;; a language server warming up a workspace.  The one on screen is the
         ;; one that was asked for.  Failing that, `buffer-list' is
         ;; most-recently-used first, so take the front.
         (opened (or (seq-find (lambda (buf) (get-buffer-window buf t)) new)
                     (car new)))
         (shown (window-buffer (selected-window))))
    (cond
     ;; A file buffer that did not exist before: this is the preview.
     (opened (preview-tab--mark opened))
     ;; Revisiting the current preview keeps it a preview.  Anything else was
     ;; already open, and stays permanent.
     ((eq shown preview-tab-buffer) (preview-tab--mark shown)))))

(defun preview-tab--invoke (fn args interactive)
  "Apply FN to ARGS, as an interactive call when INTERACTIVE.
`:around' advice sits between `call-interactively' and the command, and
`called-interactively-p' cannot see past it.  Commands that ask -- to decide
whether to message, or how much to prompt for -- would otherwise quietly
behave as though they had been called from Lisp."
  (if interactive
      (apply #'funcall-interactively fn args)
    (apply fn args)))

(defun preview-tab--call (fn args &optional interactive)
  "Apply FN to ARGS, then treat any file it opened as the preview buffer.
INTERACTIVE says the call came from `call-interactively'; see
`preview-tab--invoke'.

Reached through `preview-tab--advice' for `preview-tab-commands', and
directly from `preview-tab-find-file', which previews on request whether
or not the mode is on."
  (if preview-tab--busy
      (preview-tab--invoke fn args interactive)
    (let ((known (buffer-list))
          (preview-tab--busy t))
      ;; `unwind-protect', not `prog1'.  A command that reaches the file and
      ;; then signals -- a stale xref location, an erroring hook, plain C-g --
      ;; would otherwise leave the buffer open and tracked by nobody, which is
      ;; the one outcome this package exists to avoid.
      (unwind-protect
          (preview-tab--invoke fn args interactive)
        (preview-tab--adopt known)))))

(defun preview-tab--advice (fn &rest args)
  "Around advice on `preview-tab-commands': preview the file FN opens.
Applies FN to ARGS untouched while the mode is off.  The mode is the single
source of truth: advice that outlives it -- attached by hand, or resolved
late on a command whose package had not loaded yet -- must not go on marking
and killing buffers behind the user's back."
  ;; Read it here, in the frame `call-interactively' actually entered.
  (let ((interactive (called-interactively-p 'any)))
    (if preview-tab-mode
        (preview-tab--call fn args interactive)
      (preview-tab--invoke fn args interactive))))


;;;; Commands

;;;###autoload
(defun preview-tab-find-file (filename &optional wildcards)
  "Visit FILENAME as a preview instead of for good.
Ordinary `find-file' opens a file to keep, as in VS Code; this is the
deliberate \"just let me look at it\" counterpart.  FILENAME and WILDCARDS
are read exactly as `find-file' reads them.

A file that is already open keeps the standing it has.  Like the browsing
commands, this never demotes a buffer you have got open to a preview, which
would put a buffer you deliberately kept in line to be killed."
  (interactive (find-file-read-args "Preview file: "
                                    (confirm-nonexistent-file-or-buffer)))
  (preview-tab--call #'find-file (list filename wildcards)))

;;;###autoload
(defun preview-tab-keep ()
  "Keep the current buffer around, cancelling its preview status."
  (interactive)
  (if preview-tab--previewing
      (progn
        (preview-tab--promote)
        (message "Buffer kept"))
    (message "Not a preview buffer")))


;;;; The mode

;;;###autoload
(define-minor-mode preview-tab-mode
  "Open browsed files in a single temporary buffer, like VS Code's preview tab.

While this mode is on, the commands in `preview-tab-commands' visit files
into one preview buffer.  Opening the next one kills it; editing it, or
running `preview-tab-keep', turns it into an ordinary buffer.

Turning the mode off removes the advice and makes every preview buffer
permanent."
  :global t
  :group 'preview-tab
  (setq preview-tab--indicator-cache nil)
  (if preview-tab-mode
      (progn
        (setq preview-tab--advised (preview-tab--commands-to-advise))
        (dolist (cmd preview-tab--advised)
          (advice-add cmd :around #'preview-tab--advice))
        ;; Not `add-to-list' and `setq': `mode-line-misc-info' can be
        ;; buffer-local, and those would then edit whichever buffer happened to
        ;; be current instead of the value every buffer inherits.
        (unless (member preview-tab--mode-line-entry
                        (default-value 'mode-line-misc-info))
          (setq-default mode-line-misc-info
                        (append (default-value 'mode-line-misc-info)
                                (list preview-tab--mode-line-entry)))))
    (dolist (cmd preview-tab--advised)
      (advice-remove cmd #'preview-tab--advice))
    (setq preview-tab--advised nil)
    (setq-default mode-line-misc-info
                  (remove preview-tab--mode-line-entry
                          (default-value 'mode-line-misc-info)))
    (dolist (buf (buffer-list))
      (preview-tab--promote buf))))

(provide 'preview-tab)
;;; preview-tab.el ends here
