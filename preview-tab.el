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
;; killed.
;;
;; Two commands are provided beyond the mode itself:
;;
;;   `preview-tab-find-file'  visit a file as a preview, whatever the usual
;;                            behaviour would be -- the deliberate "just let me
;;                            look at it" counterpart to `find-file'
;;   `preview-tab-keep'       keep the current preview buffer for good
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
    consult-line
    consult-flymake)
  "Commands whose file visits are treated as temporary previews.

Commands from packages that are not installed are harmless: advice attaches
to the bare symbol and takes effect if the package is ever loaded.  This is
why third-party commands can be listed here by default.

Note that `find-file' is deliberately absent.  Like VS Code, which does not
preview from Quick Open either, typing a file name is taken as a deliberate
act; use `preview-tab-find-file' when you want the other behaviour."
  :type '(repeat function)
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
      (mapc #'face-remap-remove-relative preview-tab--face-cookies)
      (setq preview-tab--face-cookies nil)
      (force-mode-line-update))
    (when (eq (current-buffer) preview-tab-buffer)
      (setq preview-tab-buffer nil))))

(defun preview-tab--disposable-p (buffer)
  "Return non-nil if BUFFER is a preview that may be killed."
  (and (buffer-live-p buffer)
       (buffer-local-value 'preview-tab--previewing buffer)
       (not (buffer-modified-p buffer))
       (not (get-buffer-window buffer t))
       (not (get-buffer-process buffer))))

(defun preview-tab--reap (buffer)
  "Kill BUFFER if it is still an unwanted preview."
  (when (preview-tab--disposable-p buffer)
    (let ((kill-buffer-query-functions nil))
      (kill-buffer buffer))))

(defun preview-tab--mark (buffer)
  "Make BUFFER the preview buffer, retiring the previous one."
  (let ((old preview-tab-buffer))
    (setq preview-tab-buffer buffer)
    (with-current-buffer buffer
      (unless preview-tab--previewing
        (setq preview-tab--previewing t)
        (add-hook 'first-change-hook #'preview-tab--promote nil t)
        (setq preview-tab--face-cookies
              (mapcar (lambda (face) (face-remap-add-relative face 'italic))
                      preview-tab-slant-faces)))
      (force-mode-line-update))
    (when (and old (not (eq old buffer)))
      ;; The old preview is still on screen right now; let redisplay swap it out
      ;; before deciding whether it is safe to kill.
      (run-at-time 0 nil #'preview-tab--reap old))))

(defun preview-tab--call (fn &rest args)
  "Apply FN to ARGS, then treat any file it opened as the preview buffer.
Used both as `:around' advice on `preview-tab-commands' and directly by
`preview-tab-find-file'."
  (if preview-tab--busy
      (apply fn args)
    (let ((known (buffer-list))
          (preview-tab--busy t))
      (prog1 (apply fn args)
        ;; `buffer-list' is most-recently-used first, so the first hit is the
        ;; file the command just visited.
        (let ((opened (seq-find (lambda (buf)
                                  (and (buffer-file-name buf)
                                       (not (memq buf known))))
                                (buffer-list)))
              (shown (window-buffer (selected-window))))
          (cond
           ;; A file buffer that did not exist before: this is the preview.
           (opened (preview-tab--mark opened))
           ;; Revisiting the current preview keeps it a preview.  Anything else
           ;; was already open, and stays permanent.
           ((eq shown preview-tab-buffer) (preview-tab--mark shown))))))))


;;;; Commands

;;;###autoload
(defun preview-tab-find-file (filename &optional wildcards)
  "Visit FILENAME as a preview, whatever the usual behaviour would be.
Ordinary `find-file' opens a file for good, as in VS Code; this is the
deliberate \"just let me look at it\" counterpart.  FILENAME and WILDCARDS
are read exactly as `find-file' reads them."
  (interactive (find-file-read-args "Preview file: "
                                    (confirm-nonexistent-file-or-buffer)))
  (preview-tab--call #'find-file filename wildcards))

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
        (dolist (cmd preview-tab-commands)
          (advice-add cmd :around #'preview-tab--call))
        (add-to-list 'mode-line-misc-info preview-tab--mode-line-entry t))
    (dolist (cmd preview-tab-commands)
      (advice-remove cmd #'preview-tab--call))
    (setq mode-line-misc-info
          (delete preview-tab--mode-line-entry mode-line-misc-info))
    (dolist (buf (buffer-list))
      (preview-tab--promote buf))))

(provide 'preview-tab)
;;; preview-tab.el ends here
