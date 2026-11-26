;;; codex-ide-region-annotation-tests.el --- Region annotation tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'codex-ide-test-fixtures)
(require 'codex-ide)

(ert-deftest codex-ide-region-annotation-autoloads-with-session-support ()
  (with-temp-buffer
    (let ((status
           (call-process
            (or (getenv "RUN_TESTS_EMACS_EXECUTABLE")
                (expand-file-name invocation-name invocation-directory))
            nil t nil "-Q" "--batch" "-L" codex-ide-test--root-directory
            "-l" "codex-ide-autoloads"
            "--eval"
            "(let ((command 'codex-ide-annotate-region))
               (unless (and (commandp command)
                            (autoloadp (symbol-function command))
                            (not (featurep 'codex-ide-session)))
                 (error \"Expected an unloaded annotation command\"))
               (autoload-do-load (symbol-function command) command)
               (unless (and (commandp command)
                            (fboundp 'codex-ide--ensure-session-for-current-project))
                 (error \"Expected the annotation command and its session support\")))")))
      (ert-info ((buffer-string))
        (should (equal status 0))))))

(ert-deftest codex-ide-region-annotations-share-one-editable-prompt ()
  (let* ((project-dir (codex-ide-test--make-temp-project))
         (first-file (codex-ide-test--make-project-file
                      project-dir "src/first.el" "alpha\n"))
         (second-file (codex-ide-test--make-project-file
                       project-dir "src/second.el" "beta\n"))
         (notes '("Explain alpha" "Check beta"))
         (requests nil))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let ((transient-mark-mode t)
              (session (codex-ide--create-process-session)))
          (setf (codex-ide-session-thread-id session) "thread-annotations"
                (codex-ide-session-status session) "idle")
          (cl-letf (((symbol-function 'read-from-minibuffer)
                     (lambda (&rest _) (pop notes)))
                    ((symbol-function 'codex-ide--ensure-session-for-current-project)
                     (lambda () session))
                    ((symbol-function 'codex-ide--request-sync)
                     (lambda (_session method params)
                       (push (cons method params) requests)
                       nil)))
            (with-current-buffer (find-file-noselect first-file)
              (goto-char (point-min))
              (push-mark (point) t t)
              (forward-char 5)
              (activate-mark)
              (codex-ide-annotate-region))
            (with-current-buffer (find-file-noselect second-file)
              (goto-char (point-min))
              (push-mark (point) t t)
              (forward-char 4)
              (activate-mark)
              (codex-ide-annotate-region))
            (should (codex-ide-session-input-start-marker session))
            (let ((draft (with-current-buffer (codex-ide-session-buffer session)
                           (codex-ide--current-input session))))
              (should (string-match-p "Explain alpha" draft))
              (should (string-match-p "Check beta" draft))
              (should (string-match-p
                       (regexp-quote (format "Annotation for %s:1:0-1:5" first-file))
                       draft))
              (should (string-match-p
                       (regexp-quote (format "Annotation for %s:1:0-1:4" second-file))
                       draft))
              (should (string-match-p "Selected text:\nalpha" draft))
              (should (string-match-p "Selected text:\nbeta" draft))
              (should (< (string-match "Explain alpha" draft)
                         (string-match "Check beta" draft))))
            (should-not requests)
            (with-current-buffer (codex-ide-session-buffer session)
              (codex-ide-submit))
            (let ((turns (seq-filter (lambda (request)
                                       (equal (car request) "turn/start"))
                                     requests)))
              (should (= (length turns) 1))
              (let ((sent-text (alist-get 'text
                                          (aref (alist-get 'input (cdar turns)) 0))))
                (should (string-match-p "Explain alpha" sent-text))
                (should (string-match-p "Check beta" sent-text))
                (should (string-match-p "Selected text:\nalpha" sent-text))
                (should (string-match-p "Selected text:\nbeta" sent-text))))))))))

(ert-deftest codex-ide-region-annotation-preserves-draft-and-skill-binding ()
  (let* ((project-dir (codex-ide-test--make-temp-project))
         (file-path (codex-ide-test--make-project-file
                     project-dir "src/example.el" "alpha\n"))
         (default-skill-path (expand-file-name "default/SKILL.md" project-dir))
         (selected-skill-path (expand-file-name "selected/SKILL.md" project-dir))
         (draft-prefix "Review these changes with "))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let ((transient-mark-mode t)
              (session (codex-ide--create-process-session)))
          (setf (codex-ide-session-status session) "idle")
          (codex-ide--session-metadata-put
           session :skills-list
           (list `((name . "review") (enabled . t) (path . ,default-skill-path))
                 `((name . "review") (enabled . t) (path . ,selected-skill-path))))
          (codex-ide--session-metadata-put session :skills-list-state 'ready)
          (with-current-buffer (codex-ide-session-buffer session)
            (codex-ide--insert-input-prompt
             session (concat draft-prefix "$review  \n"))
            (let ((start (+ (codex-ide-session-input-start-marker session)
                            (length draft-prefix))))
              (add-text-properties
               start (+ start (length "$review"))
               (list codex-ide-mention--binding-property
                     (list :sigil "$" :kind 'skill :name "review"
                           :path selected-skill-path)))))
          (cl-letf (((symbol-function 'read-from-minibuffer)
                     (lambda (&rest _) "Check alpha"))
                    ((symbol-function 'codex-ide--ensure-session-for-current-project)
                     (lambda () session)))
            (with-current-buffer (find-file-noselect file-path)
              (goto-char (point-min))
              (push-mark (point) t t)
              (forward-char 5)
              (activate-mark)
              (codex-ide-annotate-region)))
          (with-current-buffer (codex-ide-session-buffer session)
            (let* ((draft (codex-ide--current-input session))
                   (items (codex-ide-mention-input-items draft session)))
              (should (string-prefix-p (concat draft-prefix "$review\n\n") draft))
              (should (string-match-p "Check alpha" draft))
              (should (= (length items) 1))
              (should (equal (alist-get 'path (aref items 0))
                             selected-skill-path)))))))))

(ert-deftest codex-ide-region-annotation-keeps-session-window-position ()
  (let ((project-dir (codex-ide-test--make-temp-project)))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let* ((transient-mark-mode t)
               (session (codex-ide--create-process-session))
               (buffer (codex-ide-session-buffer session))
               (window (selected-window)))
          (setf (codex-ide-session-status session) "idle")
          (with-current-buffer buffer
            (let ((inhibit-read-only t))
              (goto-char (point-min))
              (insert (mapconcat (lambda (n) (format "Transcript line %d" n))
                                 (number-sequence 1 80) "\n") "\n"))
            (codex-ide--insert-input-prompt session "Existing draft"))
          (set-window-buffer window buffer)
          (cl-letf (((symbol-function 'read-from-minibuffer)
                     (lambda (&rest _) "Check this line"))
                    ((symbol-function 'codex-ide--ensure-session-for-current-project)
                     (lambda () session)))
            (with-selected-window window
              (goto-char (point-min))
              (forward-line 18)
              (let ((start (point)))
                (push-mark start t t)
                (forward-char 15)
                (activate-mark)
                (let ((original-point (point))
                      (original-start (save-excursion
                                        (goto-char (point-min))
                                        (forward-line 10)
                                        (point))))
                  (set-window-start window original-start t)
                  (codex-ide-annotate-region)
                  (should (= (point) original-point))
                  (should (= (window-start window) original-start))
                  (should (string-match-p
                           "Check this line"
                           (codex-ide--current-input session))))))))))))

(ert-deftest codex-ide-region-annotation-requires-active-selection ()
  (with-temp-buffer
    (insert "alpha")
    (should-error (codex-ide-annotate-region) :type 'user-error)))

;;; codex-ide-region-annotation-tests.el ends here
