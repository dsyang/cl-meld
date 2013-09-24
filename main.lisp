(load "load")

(defun ccmake ( in out )
	(cl-meld:meld-compile in out)
)

(defun main()
	(ccmake (cadr *posix-argv*) (caddr *posix-argv*))
)
