(in-package :cl-meld)

(defclass ast ()
   ((definitions
      :initarg :definitions
      :initform (error "missing definitions.")
      :accessor definitions)
    (externs
      :initarg :externs
      :initform (error "missing externs.")
      :accessor externs)
    (clauses
      :initarg :clauses
      :initform (error "missing clauses.")
      :accessor clauses)
    (worker-clauses
      :initarg :worker-clauses
      :initform (error "missing worker clauses.")
      :accessor worker-clauses)
    (axioms
      :initarg :axioms
      :initform (error "missing axioms.")
      :accessor axioms)
    (worker-axioms
      :initarg :worker-axioms
      :initform (error "missing worker axioms.")
      :accessor worker-axioms)
    (functions
      :initarg :functions
      :initform (error "missing functions.")
      :accessor functions)
    (nodes
      :initarg :nodes
      :initform (error "missing nodes.")
      :accessor nodes)
	(priorities
		:initarg :priorities
		:initform (error "missing priorities.")
		:accessor priorities)
	(consts
		:initarg :consts
		:initform (error "missing consts.")
		:accessor consts)
	(args-needed
		:initarg :args-needed
		:initform (error "missing args-needed.")
		:accessor args-needed)))

(defun is-worker-clause-p (defs)
   #'(lambda (clause)
      (let ((first (find-if #'subgoal-p (clause-head clause))))
         (is-worker-definition-p (lookup-definition (subgoal-name first) defs)))))

(defun make-ast (defs externs clauses axioms funs nodes priorities consts args-needed)
   (multiple-value-bind (worker-clauses node-clauses) (split-mult-return (is-worker-clause-p defs) clauses)
      (multiple-value-bind (worker-axioms node-axioms) (split-mult-return (is-worker-clause-p defs) axioms)
         (make-instance 'ast
            :definitions defs
            :externs externs
            :clauses node-clauses
            :worker-clauses worker-clauses
            :axioms node-axioms
            :worker-axioms worker-axioms
            :functions funs
            :nodes nodes
				:priorities priorities
				:consts consts
				:args-needed args-needed))))
 
(defun merge-asts (ast1 ast2)
   "Merges two ASTs together. Note that ast1 is modified."
   (make-instance 'ast
         :definitions (nconc (definitions ast1) (definitions ast2))
         :externs (nconc (externs ast1) (externs ast2))
         :clauses (nconc (clauses ast1) (clauses ast2))
         :worker-clauses (nconc (worker-clauses ast1) (worker-clauses ast2))
         :axioms (nconc (axioms ast1) (axioms ast2))
         :worker-axioms (nconc (worker-axioms ast1) (worker-axioms ast2))
         :functions (nconc (functions ast1) (functions ast2))
         :nodes (union (nodes ast1) (nodes ast2))
			:priorities (union (priorities ast1) (priorities ast2))
			:consts (append (consts ast1) (consts ast2))
			:args-needed (max (args-needed ast1) (args-needed ast2))))

;;;;;;;;;;;;;;;;;;;
;; Clauses
;;;;;;;;;;;;;;;;;;;

(defun make-clause (perm conc &rest options) `(:clause ,perm ,conc ,options))
(defun make-axiom (conc &rest options) (make-clause nil conc options))
(defun clause-p (clause) (tagged-p clause :clause))
(defun clause-head (clause) (third clause))
(defun clause-body (clause) (second clause))
(defun set-clause-body (clause new-body)
   (setf (second clause) new-body))
(defsetf clause-body set-clause-body)
(defun set-clause-head (clause new-head)
	(setf (third clause) new-head))
(defsetf clause-head set-clause-head)

(defun clause-options (clause) (fourth clause))
(defun clause-add-option (clause opt) (push opt (fourth clause))) 
(defun clause-has-tagged-option-p (clause opt) (option-has-tag-p (clause-options clause) opt))
(defun clause-get-tagged-option (clause opt)
   (let ((res (find-if #L(tagged-p !1 opt) (clause-options clause))))
      (when res
         (rest res))))
(defun clause-get-all-tagged-options (clause opt)
   (mapfilter #'rest #L(tagged-p !1 opt) (clause-options clause)))
(defun clause-add-tagged-option (clause opt &rest rest)
   (clause-add-option clause `(,opt ,@rest)))
(defun clause-get-remote-dest (clause)
   (first (clause-get-tagged-option clause :route)))
(defun clause-is-remote-p (clause) (clause-has-tagged-option-p clause :route))
(defun clause-has-delete-p (clause) (clause-has-tagged-option-p clause :delete))
(defun clause-get-all-deletes (clause)
   (clause-get-all-tagged-options clause :delete))
(defun clause-get-delete (clause name)
   (find-if #L(string-equal (first !1) name) (clause-get-all-deletes clause)))
(defun clause-add-delete (clause name args)
   (clause-add-tagged-option clause :delete name args))
(defun clause-add-min (clause var)
	(clause-add-tagged-option clause :min var))
(defun clause-has-min-p (clause)
	(clause-has-tagged-option-p clause :min))
(defun clause-get-min-variable (clause)
	(first (clause-get-tagged-option clause :min)))
(defun clause-add-random (clause var)
	(clause-add-tagged-option clause :random var))
(defun clause-has-random-p (clause)
	(clause-has-tagged-option-p clause :random))
(defun clause-get-random-variable (clause)
	(first (clause-get-tagged-option clause :random)))
(defun clause-add-id (clause id)
	(clause-add-tagged-option clause :id id))
(defun clause-get-id (clause)
	(first (clause-get-tagged-option clause :id)))
   
(defun delete-option-args (delete-opt) (second delete-opt))
(defun delete-option-name (delete-opt) (first delete-opt))

(defun is-axiom-p (clause)
   (and (null (find-if #'subgoal-p (clause-body clause)))
         (null (find-if #'agg-construct-p (clause-body clause)))))

;;;;;;;;;;;;;;;;;;;
;; CONSTS
;;;;;;;;;;;;;;;;;;;

(defun make-constant (name expr &optional type) `(:constant ,name ,expr ,type))
(defun constant-p (c) (tagged-p c :constant))
(defun constant-name (c) (second c))
(defun constant-expr (c) (third c))
(defun constant-type (c) (fourth c))
(defun set-constant-expr (c expr)
	(setf (third c) expr))
(defsetf constant-expr set-constant-expr)

(defun set-constant-type (c newt)
	(setf (fourth c) newt))
(defsetf constant-type set-constant-type)