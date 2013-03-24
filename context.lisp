
(in-package :cl-meld)

(defparameter *file* nil "Compiled file path.")
(defparameter *ast* nil "Abstract Syntax Tree.")
(defparameter *code* nil "Virtual Machine instructions.")
(defparameter *code-rules* nil "Virtual Machine instructions for each rule.")

(define-symbol-macro *definitions* (definitions *ast*))
(define-symbol-macro *node-definitions* (remove-if #'is-worker-definition-p *definitions*))
(define-symbol-macro *worker-definitions* (filter #'is-worker-definition-p *definitions*))
(define-symbol-macro *clauses* (clauses *ast*))
(define-symbol-macro *worker-clauses* (worker-clauses *ast*))
(define-symbol-macro *axioms* (axioms *ast*))
(define-symbol-macro *const-axioms* (const-axioms *ast*))
(define-symbol-macro *worker-axioms* (worker-axioms *ast*))
(define-symbol-macro *nodes* (nodes *ast*))
(define-symbol-macro *externs* (externs *ast*))
(define-symbol-macro *functions* (functions *ast*))
(define-symbol-macro *priorities* (priorities *ast*))
(define-symbol-macro *consts* (consts *ast*))
(define-symbol-macro *processes* (processes *code*))
(define-symbol-macro *consts-code* (consts *code*))

(defun set-abstract-syntax-tree (ast) (setf *ast* ast))
