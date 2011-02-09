(in-package :cl-meld)

(define-condition type-invalid-error (error)
   ((text :initarg :text :reader text)))

(defparameter *constraints* nil)
(defparameter *defined* nil)

(defun check-home-argument (name typs)
   (when (null typs)
      (error 'type-invalid-error :text (concatenate 'string name " has no arguments")))
   (unless (type-node-p (first typs))
      (error 'type-invalid-error
         :text (concatenate 'string "first argument of tuple " name " must be of type 'node'"))))
         
(defun no-types-p (ls) (null ls))
(defun merge-types (ls types) (intersection ls types))
(defun valid-type-combination-p (types)
   (equal-or types (:type-int) (:type-float) (:type-int :type-float) (:type-bool) (:type-node)))
   
(defun variable-is-defined (var) (unless (has-elem-p *defined* (var-name var)) (push (var-name var) *defined*)))
(defun variable-defined-p (var) (has-elem-p *defined* (var-name var)))
(defun has-variables-defined (expr) (every #'variable-defined-p (all-variables expr)))

(defun set-type (expr typs)
   (cond
      ((or (var-p expr) (int-p expr)) (setf (cddr expr) (list (try-one typs))))
      ((op-p expr) (setf (cdddr expr) (list (try-one typs))))))
      
(defun force-constraint (var new-types)
   (multiple-value-bind (types ok) (gethash var *constraints*)
      (when ok
         (setf new-types (merge-types types new-types))
         (when (no-types-p new-types)
            (error 'type-invalid-error :text "type error")))
      (setf (gethash var *constraints*) new-types)))
      
(defun select-simpler-types (types) (intersection types '(:type-int)))
         
(defun get-type (expr forced-types)
   (labels ((do-get-type (expr forced-types)
            (cond
               ((var-p expr) (force-constraint (var-name expr) forced-types))
               ((int-p expr) (merge-types forced-types '(:type-int :type-float)))
               ((op-p expr)
                  (let* ((op1 (op-op1 expr)) (op2 (op-op2 expr)) (op (op-op expr))
                         (typ-oper (type-operands op forced-types)) (typ-op (type-op op forced-types)))
                     (when (no-types-p typ-op)
                        (error 'type-invalid-error :text "no types error for result or operands"))
                     (let ((t1 (get-type op1 typ-oper)) (t2 (get-type op2 typ-oper)))
                        (when (< (length t1) (length t2))
                           (setf t2 (get-type op2 t1)))
                        (when (< (length t2) (length t1))
                           (setf t1 (get-type op1 t2)))
                        (when (and (= (length t1) 2)
                                   (one-elem-p forced-types)
                                   (eq (first forced-types) :type-bool))
                           (setf t1 (get-type op1 (select-simpler-types t1)))
                           (setf t2 (get-type op2 (select-simpler-types t2))))
                        (type-oper-op op t1)))))))
      (let ((types (do-get-type expr forced-types)))
         (when (no-types-p types)
            (error 'type-invalid-error :text "type error"))
         (set-type expr types)
         types)))
      
(defun do-type-check-subgoal (defs name args &optional force-vars)
   (let ((definition (lookup-definition-types defs name)))
      (unless definition
         (format t "definition ~a~a~%" definition name)
         (error 'type-invalid-error :text "definition not found"))
      (when (not (= (length definition) (length args)))
         (error 'type-invalid-error :text "invalid number of arguments"))
      (dolist2 (arg args) (forced-type definition)
         (when (and force-vars (not (var-p arg)))
            (error 'type-invalid-error :text "only variables at body"))
         (unless (one-elem-p (get-type arg `(,forced-type)))
            (error 'type-invalid-error :text "type error"))
         (when (var-p arg)
            (variable-is-defined arg)))))
                  
(defun do-type-check-constraints (expr)
   (unless (has-variables-defined expr)
      (error 'type-invalid-error :text "all variables must be defined"))
   (let ((typs (get-type expr '(:type-bool))))
      (unless (and (one-elem-p typs) (type-bool-p (first typs)))
         (error 'type-invalid-error :text "constraint must be of type bool"))))
         
(defun update-assignment (assignments assign)
   (let* ((var (assignment-var assign)) (var-name (var-name var)))
      (multiple-value-bind (forced-types ok) (gethash var-name *constraints*)
         (let ((ty (get-type (assignment-expr assign) (if ok forced-types *all-types*))))
            (variable-is-defined var)
            (force-constraint var-name ty)
            (set-type var ty)
            (dolist (used-var (all-variables (assignment-expr assign)))
               (when-let ((other (find-if #'(lambda (a)
                                             (and (var-eq-p used-var (assignment-var a))
                                                   (not (one-elem-p (expr-type (assignment-var a))))))
                                    assignments)))
                  (update-assignment assignments other)))))))
                  
(defun assert-assignment-undefined (assignments)
   (unless (every #'(lambda (a) (not (variable-defined-p a))) (get-assignment-vars assignments))
      (error 'type-invalid-error :text "some variables are already defined")))

(defun do-type-check-assignments (body test)
   (let ((assignments (get-assignments body)))
      (loop until (every #'(lambda (a) (and (funcall test (assignment-var a)))) assignments)
            for assign = (find-if #'(lambda (a)
                                       (and (not (funcall test (assignment-var a)))
                                          (has-variables-defined (assignment-expr a))))
                                 assignments)
            do (unless assign
                  (error 'type-invalid-error :text "undefined variables"))
               (when (< 1 (count-if #L(var-eq-p (assignment-var assign) !1) (get-assignment-vars assignments)))
                  (error 'type-invalid-error :text "cannot set multiple variables"))
               (update-assignment assignments assign))))

(defun create-assignments (body)
   "Turn undefined equal constraints to assignments"
   (let (vars)
      (do-constraints body (:expr expr :orig orig)
         (let ((op1 (op-op1 expr)) (op2 (op-op2 expr)))
            (when (and (op-p expr) (equal-p expr) (var-p op1)
                        (not (variable-defined-p op1))
                        (not (has-elem-p vars (var-name op1))))
         (setf (first orig) :assign)
         (setf (second orig) op1)
         (setf (cddr orig) (list op2))
         (push (var-name op1) vars))))))

(defun transform-constants-to-constraints (clause args)
   (mapcar #'(lambda (arg)
                  (cond ((const-p arg)
                           (letret (new-var (generate-random-var))
                              (push (make-constraint (make-equal new-var '= arg))
                                    (clause-body clause))))
                         (t arg))) args))
                         
(defun transform-bodyless-clause (clause init-name)
   (setf (clause-body clause) `(,(make-subgoal init-name `(,(first (subgoal-args (first (clause-head clause)))))))))
(defun transform-bodyless-clauses (code)
   (let ((init-name (definition-name (find-if #'(lambda (d) (equal '(:init-tuple) (definition-options d)))
                              (definitions code)))))
      (do-clauses (clauses code) (:body body :clause clause)
         (unless body (transform-bodyless-clause clause init-name)))))

(defun type-check (code)
   (do-definitions code (:name name :types typs)
      (check-home-argument name typs))
   (transform-bodyless-clauses code)
   (do-clauses (clauses code) (:head head :body body :clause clause)
      (let ((*constraints* (make-hash-table))
            (*defined* nil)
            (definitions (definitions code)))
         (do-subgoals body (:args args :orig sub)
            (setf (subgoal-args sub) (transform-constants-to-constraints clause args)))
         (do-subgoals body (:name name :args args)
            (do-type-check-subgoal definitions name args t))
         (create-assignments body)
         (assert-assignment-undefined (get-assignments body))
         (do-type-check-assignments body #'typed-var-p)
         (unless (every #'variable-defined-p (all-variables (append head body)))
            (error 'type-invalid-error :text "undefined variables"))
         (do-subgoals head (:name name :args args)
            (do-type-check-subgoal definitions name args))
         (do-constraints body (:expr expr)
            (do-type-check-constraints expr))
         (do-type-check-assignments
            (setf (clause-body clause) (remove-unneeded-assignments body head))
            #'single-typed-var-p)))
   code)