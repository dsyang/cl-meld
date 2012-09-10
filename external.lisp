(in-package :cl-meld)

(define-condition external-invalid-error (error)
   ((text :initarg :text :reader text)))

(defparameter *external-functions* (make-hash-table :test #'equal))
(defparameter *external-functions-counter* 0)

(defun lookup-external-definition (name)
	(multiple-value-bind (extern found-p) (gethash name *external-functions*)
		(unless found-p
			(error 'external-invalid-error :text (tostring "invalid external function: ~a" name)))
		extern))
		
(defun lookup-external-function-id (name)
	(extern-id (lookup-external-definition name)))

(defmacro define-external-function (name ret-type types)
   `(progn
      (setf (gethash ,name *external-functions*) (make-extern ,name ,ret-type ,types *external-functions-counter*))
      (incf *external-functions-counter*)))

(define-external-function "sigmoid" :type-float '(:type-float))
(define-external-function "randint" :type-int '(:type-int))
(define-external-function "normalize" :type-list-float '(:type-list-float))
(define-external-function "damp" :type-list-float '(:type-list-float :type-list-float :type-float))
(define-external-function "divide" :type-list-float '(:type-list-float :type-list-float))
(define-external-function "convolve" :type-list-float '(:type-list-float :type-list-float))
(define-external-function "addfloatlists" :type-list-float '(:type-list-float :type-list-float))
(define-external-function "intlistlength" :type-int '(:type-list-int))
(define-external-function "intlistdiff" :type-list-int '(:type-list-int :type-list-int))
(define-external-function "intlistnth" :type-int '(:type-list-int :type-int))
(define-external-function "concatenate" :type-string '(:type-string :type-string))
(define-external-function "str2float" :type-float '(:type-string))
(define-external-function "str2int" :type-int '(:type-string))
(define-external-function "nodelistremove" :type-list-addr '(:type-list-addr :type-addr))
(define-external-function "wastetime" :type-int '(:type-int))
