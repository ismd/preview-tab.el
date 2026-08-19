EMACS   ?= emacs
PACKAGE := preview-tab
MAIN    := $(PACKAGE).el
ELPA    := .elpa

# Point NERD_ICONS at a nerd-icons checkout to exercise the icon tests:
#   make test-tty NERD_ICONS=~/.emacs.d/elpa/nerd-icons
LOAD := -L . -L test $(if $(NERD_ICONS),-L $(NERD_ICONS))

.PHONY: all compile lint test test-tty clean

all: compile lint test test-tty

## Byte-compile, treating every warning as an error.  The tests go through it
## too -- a warning there is just as much a signal, and nothing else would ever
## surface it.
compile:
	$(EMACS) -Q --batch $(LOAD) \
	  --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile $(MAIN) $(wildcard test/*.el)
	@rm -f $(PACKAGE).elc test/*.elc

$(ELPA):
	$(EMACS) -Q --batch --eval '(progn (setq package-user-dir (expand-file-name "$(ELPA)")) (require (quote package)) (add-to-list (quote package-archives) (cons "melpa" "https://melpa.org/packages/") t) (package-initialize) (package-refresh-contents) (package-install (quote package-lint)))'

## MELPA readiness: package metadata and docstring conventions.
lint: $(ELPA)
	$(EMACS) -Q --batch \
	  --eval '(setq package-user-dir (expand-file-name "$(ELPA)"))' \
	  -f package-initialize -l package-lint $(LOAD) \
	  -f package-lint-batch-and-exit $(MAIN)
	@$(EMACS) -Q --batch \
	  --eval '(progn (require (quote checkdoc)) (checkdoc-file "$(MAIN)"))' \
	  2> checkdoc.log; \
	  if [ -s checkdoc.log ]; then cat checkdoc.log; rm -f checkdoc.log; exit 1; fi; \
	  rm -f checkdoc.log
	@echo "lint: clean"

## Behavioural suite.
test:
	$(EMACS) -Q --batch $(LOAD) \
	  -l test/$(PACKAGE)-test.el -f ert-run-tests-batch-and-exit

## Frame-dependent suite.  Batch Emacs has no frame, so `format-mode-line'
## returns "" for every input there; these tests run on a terminal frame under
## a pty instead.
## TERM matters: CI runners hand us `dumb', and `emacs -nw' refuses to start on
## a terminal it cannot position the cursor on.  The typescript is kept rather
## than discarded, so a failure to even reach Emacs is visible.
TTY_TERM ?= xterm

test-tty:
	@rm -f tty-test.log typescript.log
	@TERM=$(TTY_TERM) script -qec \
	  "TERM=$(TTY_TERM) TTY_TEST_LOG=tty-test.log $(EMACS) -Q -nw $(LOAD) -l test/run-tty.el" \
	  typescript.log > /dev/null; \
	  status=$$?; \
	  if [ -f tty-test.log ]; then \
	    sed -n '/^Running/,$$p' tty-test.log; \
	  else \
	    echo "test-tty: Emacs never produced a log; the raw session follows:"; \
	    cat typescript.log; \
	    [ $$status -eq 0 ] && status=1; \
	  fi; \
	  exit $$status

clean:
	rm -f *.elc test/*.elc checkdoc.log tty-test.log typescript.log
	rm -rf $(ELPA)
