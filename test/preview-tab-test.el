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
    (defalias 'preview-tab-test-open-nested
      (lambda (name) (preview-tab-test-open name)))
    (unwind-protect
        (progn
          (advice-add 'preview-tab-test-open-nested :around #'preview-tab--advice)
          (preview-tab-test-open "a.txt")
          (preview-tab-test--settle)
          (preview-tab-test-open-nested "b.txt")
          (preview-tab-test--settle)
          (should (preview-tab-test--preview-p "b.txt"))
          (should-not (preview-tab-test--live-p "a.txt")))
      (advice-remove 'preview-tab-test-open-nested #'preview-tab--advice)
      (fmakunbound 'preview-tab-test-open-nested))))


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
