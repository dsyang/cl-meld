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
      (printdbg "Type checked. Localizing rules...")
      (localize)
      (printdbg "Localization done. Now stratifying...")
      (stratify)
      (printdbg "Stratification done."))
   *ast*)
                     
(defun do-meld-compile (file out)
   (localize-code file)
   (printdbg "Compiling AST into VM instructions...")
   (let ((compiled (compile-ast)))
      (setf *code* compiled)
      (printdbg "All compiled. Now optimizing result...")
      (optimize-code)
      (printdbg "Optimized. Now writing results to ~a" out)
      (output-code out)
      (printdbg "All done."))
   t)
       
(defun meld-compile (file out)
   (handler-case (do-meld-compile file out)
      (file-not-found-error (c) (format t "File not found: ~a~%" (text c)))
      (yacc-parse-error (c) (format t "Parse error: ~a~%" c))
      (expr-invalid-error (c) (format t "Expression error: ~a~%" (text c)))
      (type-invalid-error (c) (format t "Type error: ~a~%" (text c)))
      (localize-invalid-error (c) (format t "Localization error: ~a~%" (text c)))
      (stratification-error (c) (format t "Stratification error: ~a~%" (text c)))
      (compile-invalid-error (c) (format t "Compile error: ~a~%" (text c)))
      (output-invalid-error (c) (format t "Output error: ~a~%" (text c)))))

;; this is to be removed... soon
      
(defun create-debug-file (prog)
   (concatenate 'string "/Users/flaviocruz/Projects/meld/progs/" prog ".meld"))

(defun comp (prog &optional (out "base"))
   (meld-compile (create-debug-file prog)
                 (concatenate 'string "/Users/flaviocruz/Projects/meld/" out)))