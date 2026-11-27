;;; codex-ide-delete-session-thread-tests.el --- Tests for delete-session-thread -*- lexical-binding: t; -*-

(require 'ert)
(require 'codex-ide-test-fixtures)
(require 'codex-ide)

(ert-deftest codex-ide-delete-session-thread-closes-buffer-after-server-success ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (codex-ide-test-with-fake-processes
      (let* ((session (codex-ide--create-process-session))
             (buffer (codex-ide-session-buffer session))
             (requests nil))
        (setf (codex-ide-session-thread-id session) "live-thread")
        (cl-letf (((symbol-function 'yes-or-no-p)
                   (lambda (prompt)
                     (should (string-search (buffer-name buffer) prompt))))
                  ((symbol-function 'codex-ide--request-sync)
                   (lambda (request-session method params)
                     (should (buffer-live-p buffer))
                     (push (list request-session method params) requests))))
          (codex-ide-delete-session-thread "live-thread")
          (should (equal requests
                         (list (list session "thread/delete"
                                     '((threadId . "live-thread"))))))
          (should-not (buffer-live-p buffer)))))))

(ert-deftest codex-ide-delete-session-thread-uses-query-session-for-stored-thread ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (codex-ide-test-with-fake-processes
      (let ((session (codex-ide--create-query-session))
            (directory default-directory)
            (requests nil))
        (cl-letf (((symbol-function 'codex-ide--ensure-query-session-for-thread-selection)
                   (lambda (request-directory)
                     (should (equal request-directory directory))
                     session))
                  ((symbol-function 'yes-or-no-p)
                   (lambda (&rest _) (ert-fail "Unexpected confirmation prompt")))
                  ((symbol-function 'codex-ide--request-sync)
                   (lambda (&rest args) (push args requests))))
          (codex-ide-delete-session-thread "stored-thread" t)
          (should (equal requests
                         (list (list session "thread/delete"
                                     '((threadId . "stored-thread")))))))))))

(ert-deftest codex-ide-delete-session-thread-cancel-keeps-live-session ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (codex-ide-test-with-fake-processes
      (let ((session (codex-ide--create-process-session)))
        (setf (codex-ide-session-thread-id session) "canceled-thread")
        (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_) nil))
                  ((symbol-function 'codex-ide--request-sync)
                   (lambda (&rest _) (ert-fail "Canceled deletion contacted app-server"))))
          (should-error (codex-ide-delete-session-thread "canceled-thread")
                        :type 'user-error)
          (should (buffer-live-p (codex-ide-session-buffer session))))))))

(ert-deftest codex-ide-delete-session-thread-keeps-session-on-server-error ()
  (codex-ide-test-with-fixture (codex-ide-test--make-temp-project)
    (codex-ide-test-with-fake-processes
      (let ((session (codex-ide--create-process-session)))
        (setf (codex-ide-session-thread-id session) "failed-thread")
        (cl-letf (((symbol-function 'codex-ide--request-sync)
                   (lambda (_session method _params)
                     (should (equal method "thread/delete"))
                     (error "App-server refused to delete the thread"))))
          (should-error (codex-ide-delete-session-thread "failed-thread" t))
          (should (buffer-live-p (codex-ide-session-buffer session))))))))

(provide 'codex-ide-delete-session-thread-tests)

;;; codex-ide-delete-session-thread-tests.el ends here
