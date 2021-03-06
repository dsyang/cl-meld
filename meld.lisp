(in-package :cl-meld)

(defun localize-code (file)
   (printdbg "Parsing file ~a" file)
   (let ((ast (parse-meld-file file)))
      (set-abstract-syntax-tree ast)
      (add-base-tuples)
      (printdbg "Parsing done. Optimizing topology...")
      (optimize-topology)
      (printdbg "Topology optimized. Type-checking...")
      (type-check)
      (printdbg "Typechecked. Transforming aggregates...")
      (agg-transformer)
      (printdbg "Aggregates transformed. Localizing rules...")
      (localize)
      (printdbg "Localization done. Now stratifying...")
      (stratify)
      (printdbg "Stratification done."))
   *ast*)
                     
(defun do-meld-compile (file out &optional (is-data-p nil))
   (localize-code file)
   (printdbg "Compiling AST into VM instructions...")
   (let ((compiled (compile-ast))
			(compiled-rules (compile-ast-rules)))
      (setf *code* compiled)
		(setf *code-rules* compiled-rules)
      (printdbg "All compiled. Now optimizing result...")
      (optimize-code)
      (printdbg "Optimized. Now writing results to ~a" out)
		(if is-data-p
			(output-data-file out)
      	(output-code out))
      (printdbg "All done."))
   t)

(defun meld-compile (file out &optional (is-data-p nil))
   (format t "==> Compiling file ~a~%      to ~a.m~%" file out)
   (handler-case (do-meld-compile file out is-data-p)
      (file-not-found-error (c) (format t "File not found: ~a~%" (text c)))
      (parse-failure-error (c) (format t "Parse error at line ~a: ~a~%" (line c) (text c)))
      (expr-invalid-error (c) (format t "Expression error: ~a~%" (text c)))
      (type-invalid-error (c) (format t "Type error: ~a~%" (text c)))
      (localize-invalid-error (c) (format t "Localization error: ~a~%" (text c)))
      (stratification-error (c) (format t "Stratification error: ~a~%" (text c)))
      (compile-invalid-error (c) (format t "Compile error: ~a~%" (text c)))
		(external-invalid-error (c) (format t "External functions: ~a~%" (text c)))
      (output-invalid-error (c) (format t "Output error: ~a~%" (text c)))))

(defun meld-clear-variables ()
	(setf *ast* nil)
	(setf *code* nil)
	(setf *code-rules* nil))
	
(defun meld-compile-list (pairs)
   (loop for (in out) in pairs
         do (unless (meld-compile in out)
               (format t "PROBLEM COMPILING ~a~%" in)
					(meld-clear-variables)
					(sb-ext:gc :full t)
               (return-from meld-compile-list nil)))
   t)

;; this is to be removed... soon
      
(defun create-debug-file (prog)
   (concatenate 'string "/Users/flaviocruz/Projects/meld/" prog ".meld"))

(defun comp (prog &optional (out nil))
	(let ((output-file (if out out (pathname-name (pathname prog)))))
   	(meld-compile (create-debug-file prog)
                 	(concatenate 'string "/Users/flaviocruz/Projects/meld/" output-file))))

(defun comp-data (prog &optional (out nil))
	(let ((output-file (if out out (pathname-name (pathname prog)))))
		(meld-compile (create-debug-file prog)
			(concatenate 'string "/Users/flaviocruz/Projects/meld/" output-file) t)))