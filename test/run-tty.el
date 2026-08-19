;;; run-tty.el --- Entry point for the frame-dependent suite  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; The frame-dependent tests need a real Emacs, not a batch one, so they cannot
;; use `ert-run-tests-batch-and-exit' directly: outside batch mode ERT's output
;; goes to *Messages* rather than stderr, and there is no exit status.
;;
;; This runner waits for the terminal frame to settle, runs the suite, dumps
;; *Messages* to the log named by TTY_TEST_LOG, and exits non-zero on failure.
;; See the `test-tty' target in the Makefile.

;;; Code:

(require 'ert)
(require 'preview-tab-tty-test)

(defun preview-tab-run-tty-tests ()
  "Run the frame-dependent suite, write the log, and exit."
  (let ((log (or (getenv "TTY_TEST_LOG") "tty-test.log"))
        (stats nil))
    (unwind-protect
        (setq stats (ert-run-tests-batch t))
      (with-current-buffer (messages-buffer)
        (write-region (point-min) (point-max) log nil 'silent)))
    (kill-emacs (if (and stats (zerop (ert-stats-completed-unexpected stats)))
                    0
                  1))))

(run-with-timer 0.5 nil #'preview-tab-run-tty-tests)

(provide 'run-tty)
;;; run-tty.el ends here
