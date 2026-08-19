;;; preview-tab-tty-test.el --- Frame-dependent tests for preview-tab  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; Tests that cannot run under `emacs --batch', because batch Emacs has no
;; frame: `format-mode-line' returns the empty string for every input there.
;;
;; Run them on a terminal frame under a pty:
;;
;;     make test-tty
;;
;; The `nerd-icons' tests are skipped unless the package is on `load-path';
;; `make test-tty NERD_ICONS=/path/to/nerd-icons.el' exercises them.

;;; Code:

(require 'ert)
(require 'preview-tab)

(defvar preview-tab-tty-test--dir nil
  "Directory holding this test's scratch files.")

(defun preview-tab-tty-test--file (name)
  "Return the absolute path of scratch file NAME."
  (expand-file-name name preview-tab-tty-test--dir))

(defun preview-tab-tty-test-open (name)
  "Stand-in browsing command: visit scratch file NAME in the selected window."
  (interactive "sFile: ")
  (switch-to-buffer (find-file-noselect (preview-tab-tty-test--file name))))

(defun preview-tab-tty-test-was-interactive ()
  "Stand-in command reporting whether it was called interactively."
  (interactive)
  (called-interactively-p 'interactive))

(defun preview-tab-tty-test--settle ()
  "Let the zero-delay reap timer run."
  (dotimes (_ 5) (sit-for 0.02)))

(defun preview-tab-tty-test--misc-info (&optional window)
  "Render `mode-line-misc-info' as WINDOW would show it."
  (format-mode-line mode-line-misc-info nil (or window (selected-window))))

(defmacro preview-tab-tty-test--with-env (&rest body)
  "Run BODY with `preview-tab-mode' on and a directory of scratch files."
  (declare (indent 0) (debug t))
  `(let ((preview-tab-tty-test--dir (make-temp-file "preview-tab-tty" t))
         (preview-tab-commands '(preview-tab-tty-test-open))
         (preview-tab-buffer nil)
         (preview-tab--indicator-cache nil))
     (unwind-protect
         (progn
           (dolist (name '("a" "b"))
             (with-temp-file (preview-tab-tty-test--file (concat name ".txt"))
               (insert name "\n")))
           (preview-tab-mode 1)
           ,@body)
       (preview-tab-mode -1)
       (dolist (buf (buffer-list))
         (when (and (buffer-file-name buf)
                    (string-prefix-p preview-tab-tty-test--dir (buffer-file-name buf)))
           (with-current-buffer buf (set-buffer-modified-p nil))
           (kill-buffer buf)))
       (delete-directory preview-tab-tty-test--dir t))))


(ert-deftest preview-tab-tty-test-frame-can-render-a-mode-line ()
  "Guard the whole file: without a frame every assertion below is vacuous."
  (should (string-match-p "scratch" (format-mode-line "%b" nil nil
                                                      (get-buffer "*scratch*")))))

(ert-deftest preview-tab-tty-test-marker-renders-for-the-preview-only ()
  "The `:eval' marker shows in the preview's window and nowhere else."
  (preview-tab-tty-test--with-env
    (let ((preview-tab-indicator 'label)
          (preview-tab-label "PREVIEW"))
      (setq preview-tab--indicator-cache nil)
      (preview-tab-tty-test-open "a.txt")
      (preview-tab-tty-test--settle)
      (should (string-match-p "PREVIEW" (preview-tab-tty-test--misc-info)))
      (let ((window (split-window)))
        (unwind-protect
            (progn
              (set-window-buffer window (get-buffer "*scratch*"))
              (should-not (string-match-p "PREVIEW"
                                          (preview-tab-tty-test--misc-info window))))
          (delete-window window))))))

(ert-deftest preview-tab-tty-test-marker-disappears-on-promotion ()
  "Keeping the buffer removes the marker from its mode line."
  (preview-tab-tty-test--with-env
    (let ((preview-tab-indicator 'label)
          (preview-tab-label "PREVIEW"))
      (setq preview-tab--indicator-cache nil)
      (preview-tab-tty-test-open "a.txt")
      (preview-tab-tty-test--settle)
      (with-current-buffer (get-file-buffer (preview-tab-tty-test--file "a.txt"))
        (preview-tab-keep))
      (should (equal "" (preview-tab-tty-test--misc-info))))))

(ert-deftest preview-tab-tty-test-icon-renders-when-nerd-icons-is-available ()
  "With `nerd-icons' loaded, `auto' renders the icon in its own font."
  (skip-unless (require 'nerd-icons nil t))
  (preview-tab-tty-test--with-env
    (let ((preview-tab-indicator 'auto)
          (preview-tab-icon "nf-md-eye_outline"))
      (setq preview-tab--indicator-cache nil)
      (preview-tab-tty-test-open "a.txt")
      (preview-tab-tty-test--settle)
      (let* ((rendered (preview-tab-tty-test--misc-info))
             (glyph (char-to-string #Xf06d0)) ; nf-md-eye_outline
             (pos (string-match (regexp-quote glyph) rendered)))
        (should pos)
        ;; The icon must carry the nerd font family, or it renders as tofu in
        ;; configurations whose default font lacks the glyph.
        (should (member "Symbols Nerd Font Mono"
                        (get-text-property pos 'face rendered)))
        ;; `auto' shows one or the other, never both.
        (should-not (string-match-p "PREVIEW" rendered))))))

(ert-deftest preview-tab-tty-test-unknown-icon-name-degrades-quietly ()
  "A bad icon name must not signal from inside redisplay."
  (skip-unless (require 'nerd-icons nil t))
  (preview-tab-tty-test--with-env
    (let ((preview-tab-indicator 'icon)
          (preview-tab-icon "nf-md-there-is-no-such-icon"))
      (setq preview-tab--indicator-cache nil)
      (preview-tab-tty-test-open "a.txt")
      (preview-tab-tty-test--settle)
      (should (equal "" (preview-tab-tty-test--misc-info))))))

(ert-deftest preview-tab-tty-test-advice-keeps-called-interactively-p ()
  "An advised command still sees itself as called interactively.
`:around' advice hides `call-interactively' from `called-interactively-p',
so a command that asks would quietly change behaviour once it was listed in
`preview-tab-commands'."
  (preview-tab-tty-test--with-env
    (let ((preview-tab-commands '(preview-tab-tty-test-was-interactive)))
      (preview-tab-mode -1)
      (preview-tab-mode 1)
      (should (call-interactively #'preview-tab-tty-test-was-interactive)))))

(ert-deftest preview-tab-tty-test-find-file-reads-its-argument ()
  "`preview-tab-find-file' works through its interactive spec."
  (preview-tab-tty-test--with-env
    (let ((unread-command-events
           (listify-key-sequence
            (kbd (concat (preview-tab-tty-test--file "a.txt") " RET")))))
      (call-interactively #'preview-tab-find-file))
    (preview-tab-tty-test--settle)
    (let ((buf (get-file-buffer (preview-tab-tty-test--file "a.txt"))))
      (should (buffer-live-p buf))
      (should (preview-tab-buffer-p buf)))))

(provide 'preview-tab-tty-test)
;;; preview-tab-tty-test.el ends here
