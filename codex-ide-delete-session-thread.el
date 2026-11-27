;;; codex-ide-delete-session-thread.el --- Internal Codex thread deletion -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Duncan Gillis
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: ai, tools

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Permanent thread deletion through the Codex app-server.

;;; Code:

(require 'subr-x)

(declare-function codex-ide--ensure-query-session-for-thread-selection
                  "codex-ide-session"
                  (&optional directory))

(defun codex-ide--session-for-thread-id-any (thread-id)
  "Return any live session tracking THREAD-ID."
  (seq-find
   (lambda (session)
     (equal (codex-ide-session-thread-id session) thread-id))
   (codex-ide--session-buffer-sessions)))

(defun codex-ide--codex-home ()
  "Return the active Codex home directory."
  (expand-file-name (or (getenv "CODEX_HOME")
                        "~/.codex")))

(defun codex-ide--delete-live-thread-session (session)
  "Close SESSION after app-server deletes its thread."
  (let ((buffer (codex-ide-session-buffer session)))
    (codex-ide--teardown-session session t)
    (when (buffer-live-p buffer)
      (let ((kill-buffer-query-functions nil))
        (kill-buffer buffer)))))

;;;###autoload
(defun codex-ide-delete-session-thread (thread-id &optional skip-confirmation)
  "Delete Codex THREAD-ID from the active `CODEX_HOME`.

Use the app-server `thread/delete' API and close any attached Emacs
session buffer after the request succeeds.

When SKIP-CONFIRMATION is non-nil, delete without prompting.  This is intended
for batch callers that already presented a single confirmation."
  (interactive
   (list
    (read-string "Delete Codex thread ID: "
                 (when-let* ((session (codex-ide--get-default-session-for-current-buffer)))
                   (codex-ide-session-thread-id session)))))
  (unless (and (stringp thread-id)
               (not (string-empty-p (string-trim thread-id))))
    (user-error "Invalid thread id: %S" thread-id))
  (setq thread-id (string-trim thread-id))
  (let* ((session (codex-ide--session-for-thread-id-any thread-id))
         (buffer (and session (codex-ide-session-buffer session)))
         (buffer-name (and (buffer-live-p buffer) (buffer-name buffer))))
    (unless (or skip-confirmation
                (yes-or-no-p
                 (if buffer-name
                     (format "Delete Codex buffer %s and permanently remove thread %s from %s? "
                             buffer-name
                             thread-id
                             (abbreviate-file-name (codex-ide--codex-home)))
                   (format "Permanently remove Codex thread %s from %s? "
                           thread-id
                           (abbreviate-file-name (codex-ide--codex-home))))))
      (user-error "Canceled deletion of Codex thread %s" thread-id))
    (codex-ide--request-sync
     (or session
         (codex-ide--ensure-query-session-for-thread-selection default-directory))
     "thread/delete"
     `((threadId . ,thread-id)))
    (when session
      (codex-ide--delete-live-thread-session session))
    (message "Deleted Codex thread %s" thread-id)))

(provide 'codex-ide-delete-session-thread)

;;; codex-ide-delete-session-thread.el ends here
