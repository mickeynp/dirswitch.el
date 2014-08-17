;;; dirswitch.el --- fish-style directory switching in shells  -*- lexical-binding: t; -*-

;; Copyright (C) 2014  Mickey Petersen

;; Author: Mickey Petersen <mickey@fyeah.org>
;; Keywords: terminals, processes, tools
;; Version: 0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package adds fish-style, in-line directory switching much in
;; the same way that `M-r' grants in-line history searching in M-x
;; shell.
;;
;; dirswitch uses `dirtrack' to track the current directory and record
;; each directory switch you do in an internal ring that, much like
;; the mark or kill ring, will let you cycle through past directories.
;;
;; You must use `dirtrack-mode' and `dirtrack-mode' needs to be
;; configured first; to do this, alter `dirtrack-list' with a regular
;; expression that matches the type of prompt you use.
;;
;; For instance, the default Debian/Ubuntu prompt is
;;
;;    username@hostname:/my/directory/here$
;;
;; And a matching dirtrack regex is:
;;
;;    (setq dirtrack-list '("^[^:\\n]+@[^:\\n]+:\\(.+\\)[$#]" 1))
;;
;; You **must** also disable the built-in `shell-dirtrack-mode' which
;; monitors `cd' commands to determine your current directory. A
;; complete and working example to put in your init.el would be:
;;
;; (require 'dirswitch)
;; (defun enable-dirswitch ()
;;   (dirtrack-mode 1)
;;   (setq dirtrack-list '("^[^:\\n]+@[^:\\n]+:\\(.+\\)[$#]" 1))
;;   (shell-dirtrack-mode -1)
;;   (dirswitch-mode 1))
;;
;; (add-hook 'shell-mode-hook 'enable-dirswitch)
;;
;; Restart M-x shell and dirtracking should now work. You can then
;; cycle through past directories with `C-M-p' and `C-M-n'; press
;; `RET' to switch to the displayed directory or `ESC' or `C-g' to
;; abort.
;;
;; Known Issues:
;;
;; Terminal Emacs won't pick up RET keys correctly; this is a known
;; issue.

;;; Code:

(defvar dirswitch-max-directories 128
  "Number of directories stored in `dirswitch-directory-ring'")

(defvar dirswitch-idle-switch t
  "Switch to the selected directory after a timeout")

(defvar dirswitch--idle-timer nil
  "Internal variable that holds the idle-timer from `run-with-idle-timer'")

(defvar dirswitch-idle-switch-timer 1
  "If `dirswitch-idle-switch' is t change to the displayed directory after this delay")

(defvar dirswitch-directory-ring nil
  "Stores, as a ring, the directories visited in a `shell-mode' buffer")

(defvar-local dirswitch-directory-ring-index 0
  "Index variable to `dirswitch-directory-ring'")

(defvar-local dirswitch-overlay nil
  "Overlay property for the dirswitching prompt")

(defun dirswitch-track-directories ()
  "Remembers changed directories using `dirtrack-directory-change-hook'

Stores the new, current, directory using the variable
`default-directory'."
  (ring-insert dirswitch-directory-ring default-directory))

(defun dirswitch--switch (direction)
  "Moves in DIRECTION where direction is `prev' or `next'"
  ;; Zero out `dirswitch-directory-ring-index' if the last command was
  ;; *not* one of the dirswitching commands.
  (unless (comint-after-pmark-p)
    (comint-goto-process-mark))
  (dirswitch-switch-mode 1)
  (dirswitch-switch-enable)
  (unless (memq last-command '(dirswitch-next-directory
                               dirswitch-previous-directory))
    (setq dirswitch-directory-ring-index 0))
  ;; if there's already an overlay move it.
  (if (overlayp dirswitch-overlay)
      (move-overlay dirswitch-overlay
                    (save-excursion (forward-line 0) (point))
                    (comint-line-beginning-position))
    ;; ... otherwise create the overlay.
    (setq dirswitch-overlay
          (make-overlay (save-excursion (forward-line 0) (point))
                        (comint-line-beginning-position))))
  ;; if the overlay reaches size 0 we delete it automatically.
  (overlay-put dirswitch-overlay 'evaporate t)
  (let* ((directory-index (cond
                    ((eq direction 'prev)
                     ;; Add or subtract from the ring counter.
                     (setq dirswitch-directory-ring-index
                           (1+ dirswitch-directory-ring-index)))
                    ((eq direction 'next)
                     (setq dirswitch-directory-ring-index
                           (1- dirswitch-directory-ring-index)))))
         (directory (ring-ref dirswitch-directory-ring directory-index)))
    (overlay-put dirswitch-overlay 'display
                 (propertize
                  (format "Switch to `%s'? " directory)
                  'face 'minibuffer-prompt))
    (when dirswitch-idle-switch
        (if (timerp dirswitch--idle-timer)
           ;; cancel the timer and build a new one as the other one
           ;; has a closure around a now invalid directory.
           (cancel-timer dirswitch--idle-timer))
        ;; timer doesn't exist; make it.
        (setq dirswitch--idle-timer
              ;; this requires `lexical-binding' to be t.
              (run-with-idle-timer dirswitch-idle-switch-timer nil
                                   `(lambda () (dirswitch-switch ,directory)))))))

(defun dirswitch-previous-directory ()
  "Switches to the previous directory in the directory ring"
  (interactive)
  (dirswitch--switch 'prev))

(defun dirswitch-next-directory ()
  "Switches to the next directory in the directory ring"
  (interactive)
  (dirswitch--switch 'next))


(defvar dirswitch-switch-mode-map
  (let ((map (make-keymap)))
    (suppress-keymap map t)
    (define-key map (kbd "<return>") 'dirswitch-switch)
    (define-key map (kbd "\r") 'dirswitch-switch)
    (define-key map (kbd "C-j") 'dirswitch-switch)
    (define-key map (kbd "C-g") 'dirswitch-abort)
    (define-key map (kbd "C-M-p") 'dirswitch-previous-directory)
    (define-key map (kbd "C-M-n") 'dirswitch-next-directory)
    (define-key map (kbd "<esc>") 'dirswitch-abort)
    map)
  "Keymap for the internal `dirswitch-switch-mode' mode")

(defun dirswitch-switch (&optional directory)
  "Switches to the active `dirswitch' directory"
  (interactive)
  (dirswitch-switch-to (or directory
                           (ring-ref dirswitch-directory-ring
                                     dirswitch-directory-ring-index)))
  (dirswitch-abort))

(defun dirswitch-switch-to (directory)
  "Switches a comint buffer directory (like `shell-mode') to DIRECTORY"
  ;; there must be a better way of doing this; ideally we'd just
  ;; replace the existing prompt but that's quite hard?
  (comint-simple-send (get-buffer-process (buffer-name))
                      (concat "cd " directory "; echo")))

(defun dirswitch-abort ()
  "Aborts a `dirswitch' switch"
  (interactive)
  ;; kill the idle timer if it's running.
  (when (timerp dirswitch--idle-timer)
    (cancel-timer dirswitch--idle-timer)
    (setq dirswitch--idle-timer nil))

  (dirswitch-switch-mode -1)

  (delete-overlay dirswitch-overlay)
  ;; (setq overriding-terminal-local-map nil)
  (setq dirswitch-overlay nil))

(defun dirswitch-switch-enable ()
  ;; we need this or terminal Emacs won't work right.
  ;;
  ;; TODO: this doesn't actually fix the terminal emacs issue even
  ;; though it's what isearch does to "fix" this issue.
  ;; (setq overriding-terminal-local-map dirswitch-switch-mode-map)
  )

(define-minor-mode dirswitch-switch-mode
  "Internal mode for `dirswitch-mode'."
  nil " dirswitch" dirswitch-switch-mode-map)

(defvar dirswitch-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-M-p") 'dirswitch-previous-directory)
    (define-key map (kbd "C-M-n") 'dirswitch-next-directory)
    map)
  "Mode map for `dirswitch-mode'")

(define-minor-mode dirswitch-mode
  "Enables fast directory switching in `shell-mode'

It requires `dirtrack-mode' to work and thus it requires that
`dirtrack-list' can read and understand your prompt's format. So,
if it differs greatly from what constitutes a \"standard\" prompt
then you will most likely need to write a regular expression to
match yours.

Commands available:
\\{dirswitch-mode-map}

" nil nil dirswitch-mode-map
  (unless (eq major-mode 'shell-mode)
    (error "This command only works in `shell-mode'."))
  (setq dirswitch-directory-ring (make-ring dirswitch-max-directories))
  ;; Seed the ring with `default-directory' - the current directory.
  (ring-insert dirswitch-directory-ring default-directory)
  (if dirswitch-mode
      (add-hook 'dirtrack-directory-change-hook 'dirswitch-track-directories nil)
    (remove-hook 'dirtrack-directory-change-hook 'dirswitch-track-directories)))

(provide 'dirswitch)
;;; dirswitch.el ends here
