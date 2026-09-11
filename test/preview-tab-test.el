;;; preview-tab-test.el --- Tests for preview-tab  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Behavioural tests for preview-tab, runnable under `emacs --batch'.
;;
;; Anything that needs a real frame lives in preview-tab-tty-test.el instead.
;; Under --batch, `format-mode-line' returns the empty string for every input
;; and `called-interactively-p' returns nil even under `call-interactively', so
;; rendering and interactivity simply cannot be observed here.

;;; Code:

(require 'ert)
(require 'dired)
(require 'grep)
(require 'tab-line)

;; Not bound before Emacs 28.1, and the byte-compiler has to be told so or it
;; reads the test below as touching a free variable.
(defvar tab-line-tab-face-functions)
(require 'preview-tab)

(defvar preview-tab-test--dir nil
  "Directory holding this test's scratch files.")

(defun preview-tab-test--file (name)
  "Return the absolute path of scratch file NAME."
  (expand-file-name name preview-tab-test--dir))

(defun preview-tab-test-open (name)
  "Stand-in browsing command: visit scratch file NAME in the selected window."
  (interactive "sFile: ")
  (switch-to-buffer (find-file-noselect (preview-tab-test--file name))))

(defun preview-tab-test-open-nested (name)
  "Stand-in command reaching scratch file NAME through another command.
Models the real nesting -- `compile-goto-error' calling `next-error' --
where both ends are advised."
  (interactive "sFile: ")
  (preview-tab-test-open name))

(defun preview-tab-test-open-with-company (name)
  "Stand-in command: show scratch file NAME, and read \"e.txt\" on the side.
Models a command whose hooks or backend visit a file of their own while
they are at it."
  (interactive "sFile: ")
  (find-file-noselect (preview-tab-test--file "e.txt"))
  (display-buffer (find-file-noselect (preview-tab-test--file name))))

(defun preview-tab-test-open-then-fail (name)
  "Stand-in command: visit scratch file NAME, then signal.
Models a command that gets as far as the file and then trips over something
-- a stale location, a hook that errors."
  (interactive "sFile: ")
  (preview-tab-test-open name)
  (error "Nothing further to see here"))

(defun preview-tab-test--settle ()
  "Let the zero-delay reap timer run."
  (dotimes (_ 5) (sit-for 0.02)))

(defun preview-tab-test--live-p (name)
  "Return non-nil if a buffer visiting scratch file NAME is alive."
  (let ((buf (get-file-buffer (preview-tab-test--file name))))
    (and buf (buffer-live-p buf))))

(defun preview-tab-test--preview-p (name)
  "Return non-nil if scratch file NAME is currently the preview buffer."
  (let ((buf (get-file-buffer (preview-tab-test--file name))))
    (and buf (buffer-live-p buf) (preview-tab-buffer-p buf))))

(defun preview-tab-test--grep-buffer ()
  "Return a grep buffer listing one hit in \"a.txt\" and one in \"b.txt\".
Written out by hand rather than by running grep(1): no subprocess to wait
on, no dependency on the binary, and the same path through `compilation-mode'
either way."
  (with-current-buffer (get-buffer-create "*preview-tab-test-grep*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "-*- mode: grep; default-directory: \""
              preview-tab-test--dir "/\" -*-\n"
              "Grep started\n\n"
              (preview-tab-test--file "a.txt") ":1:a\n"
              (preview-tab-test--file "b.txt") ":1:b\n"
              "\nGrep finished\n"))
    (grep-mode)
    (goto-char (point-min))
    (current-buffer)))

(defmacro preview-tab-test--with-env (&rest body)
  "Run BODY with `preview-tab-mode' on and a directory of scratch files.
Restores global state and deletes the scratch files afterwards."
  (declare (indent 0) (debug t))
  `(let ((preview-tab-test--dir (make-temp-file "preview-tab-test" t))
         (preview-tab-commands '(preview-tab-test-open))
         (preview-tab-indicator nil)
         (preview-tab-buffer nil))
     (unwind-protect
         (progn
           (dolist (name '("a" "b" "c" "d" "e"))
             (with-temp-file (preview-tab-test--file (concat name ".txt"))
               (insert name "\n")))
           (preview-tab-mode 1)
           ,@body)
       (preview-tab-mode -1)
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf)
                    (string-prefix-p preview-tab-test--dir (buffer-file-name buf)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory preview-tab-test--dir t))))


;;;; Core lifecycle

(ert-deftest preview-tab-test-marks-the-visited-buffer ()
  "A browsing command makes the file it opened the preview buffer."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--preview-p "a.txt"))
    (should (eq preview-tab-buffer (get-file-buffer (preview-tab-test--file "a.txt"))))))

(ert-deftest preview-tab-test-next-preview-replaces-the-previous ()
  "Opening a second file kills the first preview."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (should-not (preview-tab-test--live-p "a.txt"))
    (should (preview-tab-test--preview-p "b.txt"))))

(ert-deftest preview-tab-test-revisiting-keeps-preview-status ()
  "Browsing to the current preview again leaves it a preview."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--preview-p "a.txt"))))

(ert-deftest preview-tab-test-editing-promotes ()
  "The first edit turns a preview into an ordinary buffer."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (goto-char (point-max))
      (insert "edit")
      (should-not preview-tab--previewing)
      (set-buffer-modified-p nil))
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--live-p "a.txt"))))

(ert-deftest preview-tab-test-killing-the-preview-clears-the-pointer ()
  "Killing a preview by hand must not leave a dead buffer pinned."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (kill-buffer (get-file-buffer (preview-tab-test--file "a.txt")))
    (should-not preview-tab-buffer)))

(ert-deftest preview-tab-test-keep-promotes ()
  "`preview-tab-keep' spares the buffer from the next preview."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (preview-tab-keep)
      (should-not preview-tab--previewing))
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--live-p "a.txt"))))


;;;; The real entry points
;;
;; Everything else here drives a stand-in command.  These two drive the actual
;; defaults, so that the integration itself is covered and not just the
;; bookkeeping around it.

(ert-deftest preview-tab-test-dired-find-file-previews ()
  "`dired-find-file', the flagship entry point, really does preview."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(dired-find-file))
          (dired nil))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (unwind-protect
          (progn
            (setq dired (dired-noselect preview-tab-test--dir))
            (switch-to-buffer dired)
            (goto-char (point-min))
            (should (re-search-forward "a\\.txt" nil t))
            (dired-find-file)
            (preview-tab-test--settle)
            (should (preview-tab-test--preview-p "a.txt")))
        (when dired (kill-buffer dired))))))

(ert-deftest preview-tab-test-next-error-previews-each-hit ()
  "Walking search results previews each file and lets go of the last."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(next-error))
          (grep nil))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (unwind-protect
          (progn
            (setq grep (preview-tab-test--grep-buffer))
            (switch-to-buffer grep)
            (next-error)
            (preview-tab-test--settle)
            (should (preview-tab-test--preview-p "a.txt"))
            (switch-to-buffer grep)
            (next-error)
            (preview-tab-test--settle)
            (should (preview-tab-test--preview-p "b.txt"))
            (should-not (preview-tab-test--live-p "a.txt")))
        (when grep (kill-buffer grep))))))

;; Defined by the test below, at run time and only for as long as it runs --
;; which is the very thing being tested, and which the byte-compiler has no
;; way of seeing.
(declare-function preview-tab-test-open-late "preview-tab-test" (name))

(ert-deftest preview-tab-test-command-defined-later-still-previews ()
  "A command whose package loads after the mode does still previews.
This is what lets the default list name commands from packages that may not
be installed -- Treemacs, Magit, consult.  The advice goes on the bare
symbol, and has to survive the definition arriving afterwards."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(preview-tab-test-open-late)))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (unwind-protect
          (progn
            (should-not (fboundp 'preview-tab-test-open-late))
            (defalias 'preview-tab-test-open-late
              (lambda (name)
                (interactive "sFile: ")
                (preview-tab-test-open name)))
            (preview-tab-test-open-late "a.txt")
            (preview-tab-test--settle)
            (should (preview-tab-test--preview-p "a.txt")))
        (fmakunbound 'preview-tab-test-open-late)))))

(ert-deftest preview-tab-test-magit-visit-commands-are-entry-points ()
  "Visiting a file from a Magit diff is a preview out of the box.
Magit is not a test dependency -- pulling in transient, with-editor, dash and
the rest to press RET once is not worth it -- so this checks the list the
advice is built from rather than driving the commands.  What happens once
the advice is on them is covered by
`preview-tab-test-command-defined-later-still-previews'."
  (dolist (cmd '(magit-diff-visit-file
                 magit-diff-visit-file-other-window
                 magit-diff-visit-file-other-frame
                 magit-diff-visit-worktree-file
                 magit-diff-visit-worktree-file-other-window
                 magit-diff-visit-worktree-file-other-frame))
    (should (memq cmd (default-value 'preview-tab-commands)))))


;;;; What must never be touched

(ert-deftest preview-tab-test-open-buffer-is-not-demoted ()
  "Browsing to an already open buffer leaves it permanent."
  (preview-tab-test--with-env
    (find-file-noselect (preview-tab-test--file "a.txt"))
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should-not (preview-tab-test--preview-p "a.txt"))))

(ert-deftest preview-tab-test-standing-preview-survives-a-permanent-visit ()
  "Visiting a permanent buffer does not disturb the standing preview.
This mirrors VS Code, where clicking an ordinary tab leaves the preview tab
open."
  (preview-tab-test--with-env
    (find-file-noselect (preview-tab-test--file "a.txt"))
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--live-p "b.txt"))
    (should (preview-tab-test--preview-p "b.txt"))))

(ert-deftest preview-tab-test-visible-preview-is-not-killed ()
  "A preview still shown in some window survives the next preview."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let ((window (split-window)))
      (unwind-protect
          (progn
            (set-window-buffer window (get-file-buffer (preview-tab-test--file "a.txt")))
            (preview-tab-test-open "b.txt")
            (preview-tab-test--settle)
            (should (preview-tab-test--live-p "a.txt")))
        (delete-window window)))))

(ert-deftest preview-tab-test-unkillable-preview-is-promoted ()
  "A preview that cannot be killed stops being a preview instead.
Only one preview is tracked, so once the next one takes over nothing would
ever come back for this buffer.  Leaving it flagged would strand it:
italicised and marked forever, never killed and never kept."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let ((window (split-window))
          (buffer (get-file-buffer (preview-tab-test--file "a.txt"))))
      (unwind-protect
          (progn
            (set-window-buffer window buffer)
            (preview-tab-test-open "b.txt")
            (preview-tab-test--settle)
            (should (buffer-live-p buffer))
            (should-not (preview-tab-buffer-p buffer))
            (with-current-buffer buffer
              (should-not preview-tab--face-cookies)
              (should-not (assq 'mode-line-buffer-id face-remapping-alist))))
        (delete-window window))
      ;; Now an ordinary buffer, so later previews leave it alone.
      (preview-tab-test-open "c.txt")
      (preview-tab-test--settle)
      (should (buffer-live-p buffer)))))

(ert-deftest preview-tab-test-preview-that-refuses-to-die-is-promoted ()
  "A preview `kill-buffer' turns down stops being a preview.
`preview-tab--disposable-p' cannot see a buffer-local
`kill-buffer-query-functions' -- binding the variable here only reaches the
global value -- so the kill can still be refused after we have decided to go
ahead with it."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let ((buffer (get-file-buffer (preview-tab-test--file "a.txt"))))
      (with-current-buffer buffer
        (add-hook 'kill-buffer-query-functions #'ignore nil t))
      (unwind-protect
          (progn
            (preview-tab-test-open "b.txt")
            (preview-tab-test--settle)
            (should (buffer-live-p buffer))
            (should-not (preview-tab-buffer-p buffer)))
        (with-current-buffer buffer
          (remove-hook 'kill-buffer-query-functions #'ignore t))))))

(ert-deftest preview-tab-test-modified-preview-is-not-killed ()
  "A modified preview survives even if promotion never happened."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      ;; Simulate the promotion hook not firing, leaving only the modified guard.
      (setq-local first-change-hook nil)
      (goto-char (point-max))
      (insert "dirty"))
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--live-p "a.txt"))
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (set-buffer-modified-p nil))))


;;;; Picking the right buffer

(ert-deftest preview-tab-test-adopts-the-buffer-that-is-shown ()
  "When a command opens several files, the one on screen is the preview.
Taking the most recent new buffer instead picks up whatever the command
happened to read on the side."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(preview-tab-test-open-with-company)))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (save-window-excursion
        (preview-tab-test-open-with-company "a.txt")
        (preview-tab-test--settle))
      (should (preview-tab-test--preview-p "a.txt"))
      (should-not (preview-tab-test--preview-p "e.txt")))))


(ert-deftest preview-tab-test-failing-command-still-adopts ()
  "A command that visits the file and then signals leaves a preview, not a leak.
The buffer is open either way; the only question is whether anything will
ever clean it up."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(preview-tab-test-open-then-fail)))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (should-error (preview-tab-test-open-then-fail "a.txt"))
      (preview-tab-test--settle)
      (should (preview-tab-test--preview-p "a.txt")))))


;;;; Nesting

(ert-deftest preview-tab-test-nested-commands-adopt-once ()
  "When advised commands nest, the outermost one decides."
  (preview-tab-test--with-env
    (unwind-protect
        (progn
          (advice-add 'preview-tab-test-open-nested :around #'preview-tab--advice)
          (preview-tab-test-open "a.txt")
          (preview-tab-test--settle)
          (preview-tab-test-open-nested "b.txt")
          (preview-tab-test--settle)
          (should (preview-tab-test--preview-p "b.txt"))
          (should-not (preview-tab-test--live-p "a.txt")))
      (advice-remove 'preview-tab-test-open-nested #'preview-tab--advice))))


;;;; preview-tab-find-file

(ert-deftest preview-tab-test-find-file-previews ()
  "`preview-tab-find-file' opens into the preview buffer."
  (preview-tab-test--with-env
    (preview-tab-find-file (preview-tab-test--file "a.txt"))
    (preview-tab-test--settle)
    (should (preview-tab-test--preview-p "a.txt"))
    (preview-tab-find-file (preview-tab-test--file "b.txt"))
    (preview-tab-test--settle)
    (should-not (preview-tab-test--live-p "a.txt"))
    (should (preview-tab-test--preview-p "b.txt"))))

(ert-deftest preview-tab-test-plain-find-file-stays-permanent ()
  "`find-file' is not a preview source, and spares the standing preview."
  (preview-tab-test--with-env
    (preview-tab-find-file (preview-tab-test--file "a.txt"))
    (preview-tab-test--settle)
    (find-file (preview-tab-test--file "b.txt"))
    (preview-tab-test--settle)
    (should-not (preview-tab-test--preview-p "b.txt"))
    (should (preview-tab-test--live-p "a.txt"))
    (should (preview-tab-test--preview-p "a.txt"))))


;;;; Including find-file

(ert-deftest preview-tab-test-include-find-file-previews-it ()
  "With `preview-tab-include-find-file' on, `find-file' previews."
  (preview-tab-test--with-env
    (let ((preview-tab-commands nil)
          (preview-tab-include-find-file t))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (find-file (preview-tab-test--file "a.txt"))
      (preview-tab-test--settle)
      (should (preview-tab-test--preview-p "a.txt")))))

(ert-deftest preview-tab-test-include-find-file-covers-the-whole-family ()
  "The option takes in `magit-find-file' and the window and frame variants.
Checked through the advice rather than the constant, so that it is the
commands actually taken over that are pinned down.  Magit need not be
installed for this: the advice goes on the bare symbol either way."
  (preview-tab-test--with-env
    (let ((preview-tab-commands nil)
          (preview-tab-include-find-file t))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (dolist (cmd '(find-file
                     find-file-other-window
                     find-file-other-frame
                     magit-find-file
                     magit-find-file-other-window
                     magit-find-file-other-frame))
        (should (advice-member-p #'preview-tab--advice cmd)))
      (preview-tab-mode -1))))

(ert-deftest preview-tab-test-find-file-can-be-listed-on-its-own ()
  "`find-file' can still go in `preview-tab-commands' by hand.
That is the documented way to have it without `magit-find-file', which the
option takes along."
  (preview-tab-test--with-env
    (let ((preview-tab-commands '(find-file))
          (preview-tab-include-find-file nil))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (should-not (advice-member-p #'preview-tab--advice 'magit-find-file))
      (find-file (preview-tab-test--file "a.txt"))
      (preview-tab-test--settle)
      (should (preview-tab-test--preview-p "a.txt")))))


;;;; Mode line

(ert-deftest preview-tab-test-slants-every-configured-face ()
  "A preview buffer remaps all of `preview-tab-slant-faces' to italic."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (dolist (face preview-tab-slant-faces)
        (should (memq 'italic (cdr (assq face face-remapping-alist)))))
      (should (= (length preview-tab-slant-faces)
                 (length preview-tab--face-cookies))))))

(ert-deftest preview-tab-test-promotion-removes-every-remap ()
  "Promoting a buffer undoes all of its face remapping."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (preview-tab-keep)
      (dolist (face preview-tab-slant-faces)
        (should-not (assq face face-remapping-alist)))
      (should-not preview-tab--face-cookies))))

(ert-deftest preview-tab-test-mode-line-entry-is-installed-and-removed ()
  "The mode installs its `mode-line-misc-info' entry and takes it back."
  (let ((preview-tab-commands nil))
    (preview-tab-mode 1)
    (unwind-protect
        (should (member preview-tab--mode-line-entry mode-line-misc-info))
      (preview-tab-mode -1))
    (should-not (member preview-tab--mode-line-entry mode-line-misc-info))))

(ert-deftest preview-tab-test-enabling-twice-changes-nothing ()
  "Turning the mode on again must not stack advice or mode-line entries.
Easy to do by accident -- a second `preview-tab-mode' call in a config, a
reloaded init file -- and it would show as a doubled marker."
  (preview-tab-test--with-env
    (preview-tab-mode 1)
    (preview-tab-mode 1)
    (let ((advices 0))
      (advice-mapc (lambda (&rest _) (setq advices (1+ advices)))
                   'preview-tab-test-open)
      (should (= 1 advices)))
    (should (= 1 (seq-count (lambda (entry)
                              (equal entry preview-tab--mode-line-entry))
                            (default-value 'mode-line-misc-info))))))

(ert-deftest preview-tab-test-mode-line-entry-is-global ()
  "The entry lands on the global value, whichever buffer toggles the mode.
`preview-tab-mode' is global, but `mode-line-misc-info' can be buffer-local,
and `add-to-list' would quietly have edited that local copy instead -- the
marker would then show in one buffer and nowhere else."
  (let ((preview-tab-commands nil))
    (with-temp-buffer
      (setq-local mode-line-misc-info (copy-sequence mode-line-misc-info))
      (preview-tab-mode 1)
      (unwind-protect
          (should (member preview-tab--mode-line-entry
                          (default-value 'mode-line-misc-info)))
        (preview-tab-mode -1))
      (should-not (member preview-tab--mode-line-entry
                          (default-value 'mode-line-misc-info))))))

(ert-deftest preview-tab-test-indicator-falls-back-to-the-label ()
  "Without `nerd-icons', `auto' renders the text label."
  (skip-unless (not (fboundp 'nerd-icons-mdicon)))
  (let ((preview-tab-indicator 'auto)
        (preview-tab-label "PREVIEW")
        (preview-tab--indicator-cache nil))
    (should (string-match-p "PREVIEW" (preview-tab--indicator)))))

(ert-deftest preview-tab-test-indicator-icon-only-degrades-quietly ()
  "Without `nerd-icons', `icon' renders nothing rather than erroring."
  (skip-unless (not (fboundp 'nerd-icons-mdicon)))
  (let ((preview-tab-indicator 'icon)
        (preview-tab--indicator-cache nil))
    (should (equal "" (preview-tab--indicator)))))

(ert-deftest preview-tab-test-indicator-can-be-disabled ()
  "A nil `preview-tab-indicator' renders no marker at all."
  (let ((preview-tab-indicator nil)
        (preview-tab--indicator-cache nil))
    (should (equal "" (preview-tab--indicator)))))

(ert-deftest preview-tab-test-indicator-label-mode ()
  "`label' renders the label whether or not icons are available."
  (let ((preview-tab-indicator 'label)
        (preview-tab-label "PREVIEW")
        (preview-tab--indicator-cache nil))
    (should (string-match-p "PREVIEW" (preview-tab--indicator)))))


;;;; Tab line

(defun preview-tab-test--inherits-italic-p (face)
  "Return non-nil if FACE, an anonymous face spec, pulls in `italic'."
  (and (memq 'italic (flatten-tree face)) t))

(ert-deftest preview-tab-test-tab-line-slants-a-preview-tab ()
  "The tab-line face function italicises a tab showing the preview buffer.
The face asked about is the inactive one on purpose: this is the tab as
some other window draws it, which is exactly what the buffer-local face
remapping cannot reach."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let ((buf (get-file-buffer (preview-tab-test--file "a.txt"))))
      (should (preview-tab-test--inherits-italic-p
               (preview-tab-tab-line-face buf (list buf)
                                           'tab-line-tab-inactive t nil))))))

(ert-deftest preview-tab-test-tab-line-leaves-ordinary-tabs-alone ()
  "A tab whose buffer is not the preview gets its face back untouched."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let ((buf (find-file-noselect (preview-tab-test--file "b.txt"))))
      (should (eq 'tab-line-tab-inactive
                  (preview-tab-tab-line-face buf (list buf)
                                              'tab-line-tab-inactive t nil))))))

(ert-deftest preview-tab-test-tab-line-reads-an-alist-tab ()
  "A tab given as an alist has its buffer looked up under the `buffer' key.
`tab-line-tabs-function' is free to hand out either shape, and the group
views that ship with tab-line hand out alists."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (let* ((buf (get-file-buffer (preview-tab-test--file "a.txt")))
           (tab `((name . "a.txt") (buffer . ,buf))))
      (should (preview-tab-test--inherits-italic-p
               (preview-tab-tab-line-face tab (list tab)
                                           'tab-line-tab-inactive nil nil))))))

(ert-deftest preview-tab-test-tab-line-tolerates-a-tab-without-a-buffer ()
  "A group tab carries no buffer at all; the face must come back unchanged.
This runs inside redisplay, where signalling is not an option."
  (let ((tab '((name . "group") (group-tab . t))))
    (should (eq 'tab-line-tab-inactive
                (preview-tab-tab-line-face tab (list tab)
                                            'tab-line-tab-inactive nil nil)))))

(ert-deftest preview-tab-test-tab-line-tolerates-a-dead-buffer ()
  "A tab naming a killed buffer must not signal either."
  (let ((buf (generate-new-buffer " *preview-tab-test-dead*")))
    (kill-buffer buf)
    (should (eq 'tab-line-tab-inactive
                (preview-tab-tab-line-face buf (list buf)
                                            'tab-line-tab-inactive t nil)))))

(ert-deftest preview-tab-test-tab-line-face-function-is-installed-and-removed ()
  "The mode adds its face function to the hook and takes it back.
tab-line's own entries have to survive both, or the tabs would lose the
modified and special markers for as long as the mode is on."
  (skip-unless (boundp 'tab-line-tab-face-functions))
  (let ((preview-tab-commands nil)
        (defaults (copy-sequence tab-line-tab-face-functions)))
    (preview-tab-mode 1)
    (unwind-protect
        (progn
          (should (memq #'preview-tab-tab-line-face
                        tab-line-tab-face-functions))
          (dolist (fn defaults)
            (should (memq fn tab-line-tab-face-functions))))
      (preview-tab-mode -1))
    (should-not (memq #'preview-tab-tab-line-face tab-line-tab-face-functions))
    (should (equal defaults tab-line-tab-face-functions))))

(ert-deftest preview-tab-test-marking-clears-the-tab-line-cache ()
  "Taking a buffer on as the preview invalidates the rendered tab line.
tab-line caches each window's tabs, and its cache key knows nothing about
previews: without this the tab keeps the face it was last drawn with."
  (preview-tab-test--with-env
    (set-window-parameter nil 'tab-line-cache 'stale)
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should-not (window-parameter nil 'tab-line-cache))))

(ert-deftest preview-tab-test-revisiting-the-preview-leaves-the-cache-alone ()
  "Re-marking the buffer that is already the preview must not touch the cache.
Clearing it costs every window a full re-render of its tabs, and browsing
commands re-mark the standing preview constantly -- `next-error' walking a
list of hits in one file most of all.  Nothing about the buffer changed, so
nothing should be redrawn."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (set-window-parameter nil 'tab-line-cache 'fresh)
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (should (eq 'fresh (window-parameter nil 'tab-line-cache)))))

(ert-deftest preview-tab-test-promotion-clears-the-tab-line-cache ()
  "Promoting a preview invalidates the rendered tab line as well."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (with-current-buffer (get-file-buffer (preview-tab-test--file "a.txt"))
      (set-window-parameter nil 'tab-line-cache 'stale)
      (preview-tab-keep)
      (should-not (window-parameter nil 'tab-line-cache)))))


;;;; Teardown

(ert-deftest preview-tab-test-mode-off-promotes-and-unadvises ()
  "Turning the mode off releases every preview and removes the advice."
  (preview-tab-test--with-env
    (preview-tab-test-open "a.txt")
    (preview-tab-test--settle)
    (preview-tab-mode -1)
    (should-not (preview-tab-test--preview-p "a.txt"))
    (should-not preview-tab-buffer)
    (should-not (advice-member-p #'preview-tab--advice 'preview-tab-test-open))
    ;; With the mode off, browsing kills nothing.
    (preview-tab-test-open "b.txt")
    (preview-tab-test--settle)
    (preview-tab-test-open "c.txt")
    (preview-tab-test--settle)
    (should (preview-tab-test--live-p "b.txt"))
    (preview-tab-mode 1)))

(ert-deftest preview-tab-test-mode-off-unadvises-what-it-advised ()
  "Turning the mode off undoes exactly what turning it on did.
`preview-tab-commands' may have been changed in between -- with plain `setq',
which no setter sees -- and the commands that left it must not keep the
advice."
  (preview-tab-test--with-env
    (setq preview-tab-commands nil)
    (preview-tab-mode -1)
    (should-not (advice-member-p #'preview-tab--advice 'preview-tab-test-open))))

(ert-deftest preview-tab-test-mode-off-unadvises-find-file ()
  "Turning the mode off has to let go of `find-file' as well.
It is a command the whole of Emacs calls, and advice left behind on it
would go on marking and killing buffers for the rest of the session."
  (preview-tab-test--with-env
    (let ((preview-tab-include-find-file t))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (should (advice-member-p #'preview-tab--advice 'find-file))
      (preview-tab-mode -1)
      (should-not (advice-member-p #'preview-tab--advice 'find-file)))))

(ert-deftest preview-tab-test-advice-is-inert-while-the-mode-is-off ()
  "Advice that outlives the mode must neither preview nor kill.
The mode is the single source of truth."
  (preview-tab-test--with-env
    (preview-tab-mode -1)
    ;; Put the advice back by hand, exactly as a stale one would sit there.
    (advice-add 'preview-tab-test-open :around #'preview-tab--advice)
    (unwind-protect
        (progn
          (preview-tab-test-open "a.txt")
          (preview-tab-test--settle)
          (should-not (preview-tab-test--preview-p "a.txt"))
          (should-not preview-tab-buffer)
          (preview-tab-test-open "b.txt")
          (preview-tab-test--settle)
          (should (preview-tab-test--live-p "a.txt")))
      (advice-remove 'preview-tab-test-open #'preview-tab--advice))))

(provide 'preview-tab-test)
;;; preview-tab-test.el ends here
