=====================
 Dirswitch for Emacs
=====================

This package adds fish-style, in-line directory switching much in
the same way that ``M-r`` grants in-line history searching in ``M-x
shell``.

You cycle through directories you've visited in ``shell-mode`` by
pressing ``C-M-n`` or ``C-M-p``. Dirswitch will automatically choose
the selected item after a short timeout interval or you can press
``RET`` to accept the choice immediately.

Important Installation Instructions
===================================

dirswitch uses ``dirtrack`` to track the current directory and record
each directory switch you do in an internal ring that, much like
the mark or kill ring, will let you cycle through past directories.

You must use ``dirtrack-mode`` and ``dirtrack-mode`` needs to be
configured first; to do this, alter ``dirtrack-list`` with a regular
expression that matches the type of prompt you use.

By default ``shell-dirtrack-mode`` is used; dirtrack and
``shell-dirtrack-mode`` are at odds with one another and you *must*
disable ``shell-dirtrack-mode``. See the example below.

Example Dirtrack Configuration
------------------------------

For instance, the default Debian/Ubuntu prompt is::

  username@hostname:/my/directory/here$

And a matching dirtrack regex is::

  (setq dirtrack-list '("^[^:\\n]+@[^:\\n]+:\\(.+\\)[$#]" 1))

You **must** also disable the built-in `shell-dirtrack-mode' which
monitors `cd' commands to determine your current directory. A
complete and working example to put in your init.el would be::

  (require 'dirswitch)
  (defun enable-dirswitch ()
    (dirtrack-mode 1)
    (setq dirtrack-list '("^[^:\\n]+@[^:\\n]+:\\(.+\\)[$#]" 1))
    (shell-dirtrack-mode -1)
    (dirswitch-mode 1))

  (add-hook 'shell-mode-hook 'enable-dirswitch)

Restart ``M-x shell`` and dirtracking should now work. You can then
cycle through past directories with ``C-M-p`` and ``C-M-n``; press
``RET`` to switch to the displayed directory or ``ESC`` or ``C-g`` to
abort.

Known Issues
============

This won't work right in Terminal Emacs. It's probably related to
``overriding-terminal-local-map``.

It also won't work in ``eshell``. Why? Because ``eshell`` does not use
``comint``; that's not to say it can't be made to support it, but
currently it does not.
