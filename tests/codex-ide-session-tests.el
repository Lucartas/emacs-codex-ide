;;; codex-ide-session-tests.el --- Tests for Codex session startup -*- lexical-binding: t; -*-

(require 'ert)
(require 'codex-ide-test-fixtures)
(require 'codex-ide)

(ert-deftest codex-ide-startup-rejects-older-cli-before-launch ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (dolist (output '("codex-cli 0.139.9" "codex-cli 0.140.0-alpha.1"))
      (cl-letf (((symbol-function 'codex-ide--cli-version-output) (lambda () output))
                ((symbol-function 'make-pipe-process)
                 (lambda (&rest _) (ert-fail "Started app-server with an old CLI"))))
        (let ((err (should-error (codex-ide--create-query-session)
                                 :type 'user-error)))
          (should (string-search "requires Codex CLI 0.140.0" (error-message-string err)))
          (should (string-search (substring output (length "codex-cli "))
                                 (error-message-string err))))))))

(ert-deftest codex-ide-startup-accepts-supported-cli-and-warns-on-unknown-version ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (codex-ide-test-with-fake-processes
      (dolist (output '("codex-cli 0.140.0+build.1" "codex-cli local-build"))
        (let (warnings)
          (cl-letf (((symbol-function 'codex-ide--cli-version-output) (lambda () output))
                    ((symbol-function 'display-warning)
                     (lambda (_type message &rest _) (push message warnings))))
            (should (codex-ide--live-session-p (codex-ide--create-query-session)))
            (if (string-suffix-p "local-build" output)
                (should (string-search "Could not verify Codex CLI version" (car warnings)))
              (should-not warnings))))))))

(provide 'codex-ide-session-tests)

;;; codex-ide-session-tests.el ends here
