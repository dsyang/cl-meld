(in-package :cl-meld)

(define-condition type-invalid-error (error)
   ((text :initarg :text :reader text)))

(defparameter *constraints* nil)
(defparameter *defined* nil)

(defun check-home-argument (name typs)
   (when (null typs)
      (error 'type-invalid-error :text (concatenate 'string name " has no arguments")))
   (unless (type-addr-p (first typs))
      (error 'type-invalid-error
         :text (concatenate 'string "first argument of tuple " name " must be of type 'node'"))))
         
(defun valid-aggregate-p (agg)
   (let ((agg (aggregate-agg agg))
         (typ (aggregate-type agg)))
      (case agg
         (:first t)
         ((:min :sum :max) (eq-or typ :type-int :type-float)))))

(defun check-aggregates (name typs)
   (let ((total (count-if #'aggregate-p typs)))
      (unless (<= total 1)
         (error 'type-invalid-error
            :text (concatenate 'string "tuple " name " must have only one aggregate")))
      (when-let ((agg (find-if #'aggregate-p typs)))
         (unless (valid-aggregate-p agg)
            (error 'type-invalid-error
               :text "invalid aggregate type")))))
         
(defun no-types-p (ls) (null ls))
(defun merge-types (ls types) (intersection ls types))
(defun valid-type-combination-p (types)
   (equal-or types (:type-int) (:type-float) (:type-int :type-float) (:type-bool) (:type-addr)
                   (:type-list-int) (:type-list-float) (:type-list-addr)))
   
(defun variable-is-defined (var) (unless (has-elem-p *defined* (var-name var)) (push (var-name var) *defined*)))
(defun variable-defined-p (var) (has-elem-p *defined* (var-name var)))
(defun has-variables-defined (expr) (every #'variable-defined-p (all-variables expr)))

(defun set-type (expr typs)
   (cond
      ((or (nil-p expr)) (setf (cdr expr) (list (try-one typs))))
      ((or (var-p expr) (int-p expr) (float-p expr) (tail-p expr) (head-p expr)
            (not-p expr) (test-nil-p expr) (addr-p expr) (convert-float-p expr))
         (setf (cddr expr) (list (try-one typs))))
      ((or (call-p expr) (op-p expr) (cons-p expr)) (setf (cdddr expr) (list (try-one typs))))
      (t (error 'type-invalid-error :text (tostring "Unknown expression ~a to set-type" expr)))))
      
(defun force-constraint (var new-types)
   (multiple-value-bind (types ok) (gethash var *constraints*)
      (when ok
         (setf new-types (merge-types types new-types))
         (when (no-types-p new-types)
            (error 'type-invalid-error :text
                  (tostring "Type error in variable ~a: new constraint are types ~a but variable is set as ~a" var new-types types))))
      (setf (gethash var *constraints*) new-types)))
      
(defun select-simpler-types (types)
   (cond
      ((null (set-difference types *number-types*))
       (intersection types '(:type-int)))
      ((null (set-difference  types *list-number-types*))
       (intersection types '(:type-list-int)))))

(defun list-base-type (typ)
   (case typ
      (:type-list-int :type-int)
      (:type-list-float :type-float)
      (:type-list-addr :type-addr)))
(defun list-type (typ)
   (case typ
      (:type-int :type-list-int)
      (:type-float :type-list-float)
      (:type-addr :type-list-addr)))
         
(defun get-type (expr forced-types defs)
   (labels ((do-get-type (expr forced-types)
            (cond
               ((var-p expr) (force-constraint (var-name expr) forced-types))
               ((int-p expr) (merge-types forced-types '(:type-int :type-float)))
               ((float-p expr) (merge-types forced-types '(:type-float)))
               ((addr-p expr) (merge-types forced-types '(:type-addr)))
               ((call-p expr)
                  (let ((extern (lookup-extern defs (call-name expr))))
                     (unless extern (error 'type-invalid-error :text "undefined call"))
                     (loop for typ in (extern-types extern)
                           for arg in (call-args expr)
                           do (get-type arg `(,typ) defs))
                     (merge-types forced-types `(,(extern-ret-type extern)))))
               ((convert-float-p expr)
                  (get-type (convert-float-expr expr) '(:type-int) defs)
                  (merge-types forced-types '(:type-float)))
               ((nil-p expr) (merge-types forced-types *list-types*))
               ((cons-p expr)
                  (let* ((tail (cons-tail expr))
                         (head (cons-head expr))
                         (base-types (mapcar #'list-base-type forced-types))
                         (head-types (get-type head base-types defs))
                         (new-types (merge-types (mapcar #'list-type head-types) forced-types)))
                     (get-type tail new-types defs)))
               ((head-p expr)
                  (let ((ls (head-list expr))
                        (list-types (mapcar #'list-type forced-types)))
                     (mapcar #'list-base-type (get-type ls list-types defs))))
               ((tail-p expr)
                  (get-type (tail-list expr) forced-types defs))
               ((not-p expr)
                  (merge-types forced-types (get-type (not-expr expr) '(:type-bool) defs))) 
               ((test-nil-p expr)
                  (get-type (test-nil-expr expr) *list-types* defs)
                  (merge-types forced-types '(:type-bool)))
               ((op-p expr)
                  (let* ((op1 (op-op1 expr)) (op2 (op-op2 expr)) (op (op-op expr))
                         (typ-oper (type-operands op forced-types)) (typ-op (type-op op forced-types)))
                     (when (no-types-p typ-op)
                        (error 'type-invalid-error :text "no types error for result or operands"))
                     (let ((t1 (get-type op1 typ-oper defs)) (t2 (get-type op2 typ-oper defs)))
                        (when (< (length t1) (length t2))
                           (setf t2 (get-type op2 t1 defs)))
                        (when (< (length t2) (length t1))
                           (setf t1 (get-type op1 t2 defs)))
                        (when (and (= (length t1) 2) (one-elem-p forced-types) (eq (first forced-types) :type-bool))
                           (setf t1 (get-type op1 (select-simpler-types t1) defs))
                           (setf t2 (get-type op2 (select-simpler-types t2) defs)))
                        (type-oper-op op t1))))
               (t (error 'type-invalid-error :text (tostring "Unknown expression ~a to typecheck" expr))))))
      (let ((types (do-get-type expr forced-types)))
         (when (no-types-p types)
            (error 'type-invalid-error :text (tostring "Type error in expression ~a: wanted types ~a" expr forced-types)))
         (set-type expr types)
         types)))
      
(defun do-type-check-subgoal (defs name args &optional force-vars)
   (let ((definition (lookup-definition-types defs name)))
      (unless definition
         (error 'type-invalid-error :text (concatenate 'string "Definition " name " not found")))
      (when (not (= (length definition) (length args)))
         (error 'type-invalid-error :text (tostring "Invalid number of arguments in subgoal ~a~a" name args)))
      (dolist2 (arg args) (forced-type (definition-arg-types definition))
         (when (and force-vars (not (var-p arg)))
            (error 'type-invalid-error :text "only variables at body"))
         (unless (one-elem-p (get-type arg `(,forced-type) defs))
            (error 'type-invalid-error :text "type error"))
         (when (var-p arg)
            (variable-is-defined arg)))))

(defun do-type-check-constraints (expr defs)
   (unless (has-variables-defined expr)
      (error 'type-invalid-error :text "all variables must be defined"))
   (let ((typs (get-type expr '(:type-bool) defs)))
      (unless (and (one-elem-p typs) (type-bool-p (first typs)))
         (error 'type-invalid-error :text "constraint must be of type bool"))))

(defun update-assignment (assignments assign defs)
   (let* ((var (assignment-var assign)) (var-name (var-name var)))
      (multiple-value-bind (forced-types ok) (gethash var-name *constraints*)
         (let ((ty (get-type (assignment-expr assign) (if ok forced-types *all-types*) defs)))
            (variable-is-defined var)
            (force-constraint var-name ty)
            (set-type var ty)
            (dolist (used-var (all-variables (assignment-expr assign)))
               (when-let ((other (find-if #'(lambda (a)
                                             (and (var-eq-p used-var (assignment-var a))
                                                   (not (one-elem-p (expr-type (assignment-var a))))))
                                    assignments)))
                  (update-assignment assignments other defs)))))))
                  
(defun assert-assignment-undefined (assignments)
   (unless (every #'(lambda (a) (not (variable-defined-p a))) (get-assignment-vars assignments))
      (error 'type-invalid-error :text "some variables are already defined")))

(defun do-type-check-assignments (body test defs)
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
               (update-assignment assignments assign defs))))

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
         
(defun unfold-cons (mangled-var cons clause)
   (let ((tail-var (generate-random-var))
         (tail (cons-tail cons)))
      (push (make-constraint (make-not (make-test-nil mangled-var)) 100) (clause-body clause))
      (push (make-constraint (make-equal (cons-head cons) '= (make-head mangled-var))) (clause-body clause))
      (cond
         ((cons-p tail)
            (push (make-constraint (make-equal tail-var '= (make-tail mangled-var))) (clause-body clause))
            (unfold-cons tail-var tail clause))
         (t
            (push (make-constraint (make-equal tail '= (make-tail mangled-var))) (clause-body clause))))))

(defun transform-constant-to-constraint (clause arg)
   (cond ((const-p arg)
            (letret (new-var (generate-random-var))
               (if (cons-p arg)
                  (unfold-cons new-var arg clause)
                  (push (make-constraint (make-equal new-var '= arg)) (clause-body clause)))))
          (t arg)))
(defun transform-constants-to-constraints (clause args)
   (mapcar #L(transform-constant-to-constraint clause !1) args))
                         
(defun transform-bodyless-clause (clause init-name)
   (setf (clause-body clause) `(,@(clause-body clause) ,(make-subgoal init-name `(,(first (subgoal-args (first (clause-head clause)))))))))
(defun transform-bodyless-clauses (code)
   (let ((init-name (definition-name (find-if #'(lambda (d) (equal '(:init-tuple) (definition-options d)))
                              (definitions code)))))
      (do-clauses (clauses code) (:body body :clause clause)
         (unless (filter #'subgoal-p body) (transform-bodyless-clause clause init-name)))))

(defun add-variable-head (code)
   (do-clauses (clauses code) (:clause clause :head head)
      (do-subgoals head (:args args :orig sub)
         (setf (first (subgoal-args sub)) (transform-constant-to-constraint clause
                        (first args))))))

(defun type-check (code)
   (do-definitions code (:name name :types typs)
      (check-home-argument name typs)
      (check-aggregates name typs))
   (add-variable-head code)
   (transform-bodyless-clauses code)
   (do-clauses (clauses code) (:clause clause :body body)
      (do-subgoals body (:args args :orig sub)
         (setf (subgoal-args sub) (transform-constants-to-constraints clause args))))
   (do-clauses (clauses code) (:head head :body body :clause clause)
      (let ((*constraints* (make-hash-table))
            (*defined* nil)
            (definitions (all-definitions code)))
         (do-subgoals body (:name name :args args)
            (do-type-check-subgoal definitions name args t))
         (create-assignments body)
         (assert-assignment-undefined (get-assignments body))
         (do-type-check-assignments body #'typed-var-p definitions)
         (unless (every #'variable-defined-p (all-variables (append head body)))
            (error 'type-invalid-error :text "undefined variables"))
         (do-subgoals head (:name name :args args)
            (do-type-check-subgoal definitions name args))
         (do-constraints body (:expr expr)
            (do-type-check-constraints expr definitions))
         (do-type-check-assignments
            (setf (clause-body clause) (remove-unneeded-assignments body head))
            #'single-typed-var-p definitions)))
   code)
