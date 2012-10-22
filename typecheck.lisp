(in-package :cl-meld)

(define-condition type-invalid-error (error)
   ((text :initarg :text :reader text)))

(defun check-home-argument (name typs)
   (when (null typs)
      (error 'type-invalid-error :text (concatenate 'string name " has no arguments")))
   (unless (or (type-addr-p (first typs))
               (type-worker-p (first typs)))
      (error 'type-invalid-error
         :text (concatenate 'string "first argument of tuple " name " must be of type 'node' or 'worker'"))))
         
(defun no-types-p (ls) (null ls))
(defun merge-types (ls types) (intersection ls types))
(defun valid-type-combination-p (types)
   (equal-or types (:type-int) (:type-float) (:type-int :type-float) (:type-bool) (:type-addr) (:type-worker)
                   (:type-list-int) (:type-list-float) (:type-list-addr) (:type-string)))
   
(defparameter *constraints* nil)
(defparameter *defined* nil)
(defparameter *defined-in-context* nil)

(defmacro with-typecheck-context (&body body)
   `(let ((*defined* nil)
          (*defined-in-context* nil)
          (*constraints* (make-hash-table)))
      ,@body))

(defmacro extend-typecheck-context (&body body)
   `(let ((*defined* (copy-list *defined*))
          (*defined-in-context* nil)
          (*constraints* (copy-hash-table *constraints*)))
      ,@body))

(defun variable-is-defined (var)
   (unless (has-elem-p *defined* (var-name var))
      (push (var-name var) *defined-in-context*)
      (push (var-name var) *defined*)))
(defun variable-defined-p (var) (has-elem-p *defined* (var-name var)))
(defun has-variables-defined (expr) (every #'variable-defined-p (all-variables expr)))

(defun set-type (expr typs)
   (let ((typ (list (try-one typs))))
      (cond
         ((or (nil-p expr) (world-p expr)) (setf (cdr expr) typ))
         ((or (var-p expr) (int-p expr) (float-p expr) (string-constant-p expr) (tail-p expr) (head-p expr)
               (not-p expr) (test-nil-p expr) (addr-p expr) (convert-float-p expr)
					(get-constant-p expr))
            (setf (cddr expr) typ))
         ((or (call-p expr) (op-p expr) (cons-p expr) (colocated-p expr)) (setf (cdddr expr) typ))
         ((or (let-p expr) (if-p expr)) (setf (cddddr expr) typ))
			((or (argument-p expr))) ; do nothing
         (t (error 'type-invalid-error :text (tostring "set-type: Unknown expression ~a" expr))))))
      
(defun force-constraint (var new-types)
   (multiple-value-bind (types ok) (gethash var *constraints*)
      (when ok
			(setf new-types (merge-types types new-types))
         (when (no-types-p new-types)
            (error 'type-invalid-error :text
                  (tostring "Type error in variable ~a: new constraint are types ~a but variable is set as ~a" var new-types types))))
      (set-var-constraint var new-types)))

(defun set-var-constraint (var new-types)
	(assert (listp new-types))
	(setf (gethash var *constraints*) new-types))
(defun get-var-constraint (var)
   (gethash var *constraints*))
   
(defun select-simpler-types (types)
   (cond
      ((set-equal-p types *number-types*)
       (intersection types '(:type-int)))
      ((set-equal-p types *list-number-types*)
       (intersection types '(:type-list-int)))
		(t types)))

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
         
(defun get-type (expr forced-types)
   (labels ((do-get-type (expr forced-types)
            (cond
					((string-constant-p expr) (merge-types forced-types '(:type-string)))
               ((var-p expr) (force-constraint (var-name expr) forced-types))
               ((int-p expr) (merge-types forced-types '(:type-int :type-float)))
               ((float-p expr) (merge-types forced-types '(:type-float)))
               ((addr-p expr) (merge-types forced-types '(:type-addr)))
					((argument-p expr) (merge-types forced-types '(:type-string)))
					((get-constant-p expr)
						(with-get-constant expr (:name name)
							(let ((const (lookup-const name)))
								(unless const
									(error 'type-invalid-error :text
										(tostring "could not find constant ~a" name)))
								(merge-types forced-types (list (constant-type const))))))
               ((if-p expr)
                  (get-type (if-cmp expr) '(:type-bool))
                  (let ((t1 (get-type (if-e1 expr) forced-types))
                        (t2 (get-type (if-e2 expr) forced-types)))
                     (unless (equal t1 t2)
                        (error 'type-invalid-error :text
                              (tostring "expressions ~a and ~a must have equal types" (if-e1 expr) (if-e2 expr))))
                     t1))
               ((call-p expr)
                  (let ((extern (lookup-external-definition (call-name expr))))
                     (unless extern (error 'type-invalid-error :text (tostring "undefined call ~a" (call-name expr))))
                     (when (not (= (length (extern-types extern)) (length (call-args expr))))
								(error 'type-invalid-error :text
									(tostring "external call ~a has invalid number of arguments (should have ~a arguments)"
										extern (length (extern-types extern)))))
							(loop for typ in (extern-types extern)
                           for arg in (call-args expr)
                           do (get-type arg `(,typ)))
                     (merge-types forced-types `(,(extern-ret-type extern)))))
               ((let-p expr)
                  (if (variable-defined-p (let-var expr))
                     (error 'type-invalid-error :text (tostring "Variable ~a in LET is already defined" (let-var expr))))
                  (let* (ret
                         constraints
                         (var (let-var expr))
                         (typ-expr (get-type (let-expr expr) *all-types*)))
                     (extend-typecheck-context
                        (force-constraint (var-name var) typ-expr)
                        (variable-is-defined var)
                        (setf ret (get-type (let-body expr) forced-types))
                        (setf constraints (get-var-constraint (var-name var))))
                     (when (and (equal typ-expr constraints)
                                 (> (length constraints) 1))
                        
                        (error 'type-invalid-error :text
                              (tostring "Type of variable ~a cannot be properly defined. Maybe it is not being used in the LET?" var)))
                     (get-type (let-expr expr) constraints) 
                     ret
                  ))
               ((convert-float-p expr)
                  (get-type (convert-float-expr expr) '(:type-int))
                  (merge-types forced-types '(:type-float)))
               ((nil-p expr) (merge-types forced-types *list-types*))
               ((world-p expr) (merge-types '(:type-int) forced-types))
               ((colocated-p expr)
                  (get-type (colocated-first expr) '(:type-addr))
                  (get-type (colocated-second expr) '(:type-addr))
                  (merge-types forced-types '(:type-bool)))
               ((cons-p expr)
                  (let* ((tail (cons-tail expr))
                         (head (cons-head expr))
                         (base-types (mapcar #'list-base-type forced-types))
                         (head-types (get-type head base-types))
                         (new-types (merge-types (mapcar #'list-type head-types) forced-types)))
                     (get-type tail new-types)))
               ((head-p expr)
                  (let ((ls (head-list expr))
                        (list-types (mapcar #'list-type forced-types)))
                     (mapcar #'list-base-type (get-type ls list-types))))
               ((tail-p expr)
                  (get-type (tail-list expr) forced-types))
               ((not-p expr)
                  (merge-types forced-types (get-type (not-expr expr) '(:type-bool)))) 
               ((test-nil-p expr)
                  (get-type (test-nil-expr expr) *list-types*)
                  (merge-types forced-types '(:type-bool)))
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
                        (when (and (= (length t1) 2) (one-elem-p forced-types) (eq (first forced-types) :type-bool))
                           (setf t1 (get-type op1 (select-simpler-types t1)))
                           (setf t2 (get-type op2 (select-simpler-types t2))))
                        (type-oper-op op t1))))
               (t (error 'type-invalid-error :text (tostring "get-type: Unknown expression ~a" expr))))))
      (let ((types (do-get-type expr forced-types)))
         (when (no-types-p types)
            (error 'type-invalid-error :text (tostring "Type error in expression ~a: wanted types ~a" expr forced-types)))
         (set-type expr types)
         types)))
      
(defun do-type-check-subgoal (name args options &key (body-p nil) (axiom-p nil))
	(let* ((def (lookup-definition name))
          (definition (definition-types def)))
      (unless def
         (error 'type-invalid-error :text (concatenate 'string "Definition " name " not found")))
      (when (not (= (length definition) (length args)))
         (error 'type-invalid-error :text (tostring "Invalid number of arguments in subgoal ~a~a" name args)))
      (cond
         ((is-linear-p def) ;; linear fact
            (dolist (opt options)
               (case opt
                  (:reuse
                     (unless body-p
                        (error 'type-invalid-error :text (tostring "Linear reuse of facts must be used in the body, not the head: ~a" name))))
                  (:persistent
                     (error 'type-invalid-error :text (tostring "Only persistent facts may use !: ~a" name)))
						(:random)
                  (otherwise
                     (error 'type-invalid-error :text (tostring "Unrecognized option ~a for subgoal ~a" opt name))))))
         (t ;; persistent fact
            (let ((has-persistent-p nil))
               (dolist (opt options)
                  (case opt
                     (:reuse
                        (error 'type-invalid-error :text (tostring "Reuse option $ may only be used with linear facts: ~a" name)))
                     (:persistent
                        (setf has-persistent-p t))
							(:random)
                     (otherwise
                        (error 'type-invalid-error :text (tostring "Unrecognized option ~a for subgoal ~a" opt name)))))
               (unless has-persistent-p
                  (warn (tostring "Subgoal ~a needs to have a !" name))))))
      (dolist2 (arg args) (forced-type (definition-arg-types definition))
			(assert arg)
         (when (and body-p (not (var-p arg)))
            (error 'type-invalid-error :text (tostring "only variables at body: ~a (~a)" name arg)))
         (unless (one-elem-p (get-type arg `(,forced-type)))
            (error 'type-invalid-error :text "type error"))
         (when (var-p arg)
            (if (and (not body-p) (not (variable-defined-p arg)))
               (error 'type-invalid-error :text (tostring "undefined variable: ~a" arg)))
            (if body-p
               (variable-is-defined arg))))))

(defun do-type-check-agg-construct (c in-body-p)
   (with-agg-construct c (:body body :head head :to to :op op)
      (let ((old-defined *defined*)
            (types nil))
         (extend-typecheck-context
				(transform-agg-constructs-constants c)
				(type-check-body body)
				(case op
					(:collect
						(let* ((vtype (get-var-constraint (var-name to)))
								 (vtype-list (mapcar #'list-type vtype)))
							(assert (= 1 (length vtype)))
							(set-type to vtype-list)
							(set-var-constraint (var-name to) vtype-list)))
					(:count
						(variable-is-defined to)
						(set-type to '(:type-int))
						(set-var-constraint (var-name to) '(:type-int)))		
					)
				(setf (agg-construct-body c)
					(type-check-all-except-body body head :check-comprehensions nil :check-agg-constructs nil :axiom-p nil))
            (let ((new-ones *defined-in-context*)
						(target-variables (mapcar #'var-name (agg-construct-vlist c))))
               (when (or (eq op :sum)
								 (eq op :collect)
								 (eq op :count))
                  (push (var-name to) target-variables))
               (unless (subsetp new-ones target-variables)
                  (error 'type-invalid-error :text (tostring "Aggregate ~a is using more variables than it specifies ~a -> ~a" c new-ones target-variables)))
               (unless (subsetp target-variables new-ones)
                  (error 'type-invalid-error :text (tostring "Aggregate ~a is not using enough variables ~a ~a" c target-variables new-ones))))
               (setf types (get-var-constraint (var-name to))))
         (when in-body-p
				(case op
            	(:count
               	(force-constraint (var-name to) '(:type-int))
               	(variable-is-defined to))
            	(:sum
               	(get-type to types)
               	(variable-is-defined to))
            	(otherwise
               	(error 'type-invalid-error :text (tostring "Unrecognized aggregate operator ~a" op))))))))

(defun do-type-check-constraints (expr)
   ;; LET has problems with this
	;(unless (has-variables-defined expr)
   ;   (error 'type-invalid-error :text (tostring "all variables must be defined: ~a , ~a" expr (all-variables expr))))
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
      (do-constraints body (:expr expr :constraint orig)
         (let ((op1 (op-op1 expr)) (op2 (op-op2 expr)))
            (when (and (op-p expr) (equal-p expr) (var-p op1)
                        (not (variable-defined-p op1))
                        (not (has-elem-p vars (var-name op1))))
         ;; changes constraints to assignments
         (setf (first orig) :assign)
         (setf (second orig) op1)
         (setf (cddr orig) (list op2))
         (push (var-name op1) vars))))))

(defun unfold-cons (mangled-var cons)
   (let* ((tail-var (generate-random-var))
          (tail (cons-tail cons))
			 (c1 (make-constraint (make-not (make-test-nil mangled-var)) 100))
			 (c2 (make-constraint (make-equal (cons-head cons) '= (make-head mangled-var)))))
      (cond
         ((cons-p tail)
				(multiple-value-bind (new-constraints new-vars)
						(unfold-cons tail-var tail)
					(values (append `(,c1 ,c2
									,(make-constraint (make-equal tail-var '= (make-tail mangled-var))))
									new-constraints)
							`(,tail-var ,@new-vars))))
         (t
				(values `(,c1 ,c2 ,(make-constraint (make-equal tail '= (make-tail mangled-var))))
							`(,tail-var))))))

(defun transform-constant-to-constraint (arg &optional only-addr-p)
   (cond
		((const-p arg)
          (let ((new-var (generate-random-var)))
             (if (and (not only-addr-p) (cons-p arg))
					(multiple-value-bind (new-constraints new-vars)
							(unfold-cons new-var arg)
						(values new-var new-constraints `(,new-var ,@new-vars)))
					(values new-var
							`(,(make-constraint (make-equal new-var '= arg)))
							`(,new-var)))))
      (t (values arg nil nil))))

(defun transform-constants-to-constraints-clause (clause args &optional only-addr-p)
   (mapcar #'(lambda (arg)
						(multiple-value-bind (new-arg new-constraints)
							(transform-constant-to-constraint arg only-addr-p)
							(dolist (new-constraint new-constraints)
								(assert (constraint-p new-constraint))
								(push-end new-constraint (clause-body clause)))
							new-arg))
				args))
				
(defun transform-clause-constants (clause)
   (do-subgoals (clause-body clause) (:args args :subgoal sub)
      (setf (subgoal-args sub) (transform-constants-to-constraints-clause clause args))))

(defun transform-constants-to-constraints-agg-construct (c args &optional only-addr-p)
   (mapcar #'(lambda (arg)
						(multiple-value-bind (new-arg new-constraints new-vars)
							(transform-constant-to-constraint arg only-addr-p)
							(when new-vars
								(setf (agg-construct-vlist c) (append (agg-construct-vlist c) new-vars)))
							(dolist (new-constraint new-constraints)
								(assert (constraint-p new-constraint))
								(push-end new-constraint (agg-construct-body c)))
							new-arg))
				args))
				
(defun transform-agg-constructs-constants (c)
	(do-subgoals (agg-construct-body c) (:args args :subgoal sub)
		(setf (subgoal-args sub) (transform-constants-to-constraints-agg-construct c args))))

(defun add-variable-head-clause (clause)
   (do-subgoals (clause-head clause) (:args args :subgoal sub)
		(multiple-value-bind (new-arg constraints)
			(transform-constant-to-constraint (first args))
			(dolist (constraint constraints)
				(push constraint (clause-body clause)))
			(setf (first (subgoal-args sub)) new-arg))))
                     
(defun add-variable-head ()
   (do-rules (:clause clause)
      (add-variable-head-clause clause))
   (do-axioms (:clause clause)
      (add-variable-head-clause clause)))
      
(defun do-type-check-comprehension (comp)
   (let ((target-variables (mapcar #'var-name (comprehension-variables comp))))
      (extend-typecheck-context
         (with-comprehension comp (:left left :right right)
				(setf (comprehension-left comp)
					(type-check-body-and-head left right :check-comprehensions nil :axiom-p nil)))
         ;; check if the set of new defined variables is identical to target-variables
         (let ((new-ones *defined-in-context*))
            (unless (subsetp new-ones target-variables)
               (error 'type-invalid-error :text (tostring "Comprehension ~a is using more variables than it specifies" comp)))
            (unless (subsetp target-variables new-ones)
               (error 'type-invalid-error :text (tostring "Comprehension ~a is not using enough variables ~a ~a" comp target-variables new-ones)))))))
      
(defun type-check-body (body)
	(do-subgoals body (:name name :args args :options options)
      (do-type-check-subgoal name args options :body-p t))
   (do-agg-constructs body (:agg-construct c)
      (do-type-check-agg-construct c t))
   (create-assignments body)
   (assert-assignment-undefined (get-assignments body))
   (do-type-check-assignments body #'typed-var-p)
	(do-constraints body (:expr expr)
      (do-type-check-constraints expr)))

(defun type-check-all-except-body (body head &key check-comprehensions check-agg-constructs axiom-p)
	(do-subgoals head (:name name :args args :options options)
      (do-type-check-subgoal name args options :axiom-p axiom-p))
   (when check-comprehensions
		(do-comprehensions head (:comprehension comp)
      	(do-type-check-comprehension comp)))
	(when check-agg-constructs
		(do-agg-constructs head (:agg-construct c)
			(do-type-check-agg-construct c nil)))
	(let ((new-body (remove-unneeded-assignments body head)))
   	(do-type-check-assignments new-body	#'single-typed-var-p)
		new-body))
		
(defun type-check-body-and-head (body head &key check-comprehensions check-agg-constructs axiom-p)
	(type-check-body body)
	(type-check-all-except-body body head :check-comprehensions check-comprehensions
													  :check-agg-constructs check-agg-constructs
													  :axiom-p axiom-p))
																		
(defun type-check-clause (head body clause axiom-p)
   (with-typecheck-context
      (variable-is-defined (first-host-node head))
		(setf (clause-body clause)
			(type-check-body-and-head body head :check-comprehensions t :check-agg-constructs t :axiom-p axiom-p))
		;; add :random to every subgoal with such variable
		(when (clause-has-random-p clause)
			(let ((var (clause-get-random-variable clause)))
				(unless (variable-defined-p var)
					(error 'type-invalid-error :text
						(tostring "can't randomize variable ~a because such variable is not defined in the subgoal body" var)))
				(do-subgoals body (:subgoal sub)
					(when (subgoal-has-var-p sub var)
						(subgoal-add-option sub :random)))))
		;; add :min to every subgoal with such variable
		(when (clause-has-min-p clause)
			(let ((var (clause-get-min-variable clause))
					(involved-variables nil))
				(unless (variable-defined-p var)
					(error 'type-invalid-error :text
						(tostring "can't minimize variable ~a because such variable is not defined in the subgoal body" var)))
				(do-subgoals body (:subgoal sub)
					(when (subgoal-has-var-p sub var)
						(subgoal-add-min sub var)
						(with-subgoal sub (:args args)
							(dolist (arg (rest args))
								(unless (var-eq-p var arg)
									(push arg involved-variables))))))
				;; mark subgoals that use the same variables (involved-variables)
				(do-subgoals body (:subgoal sub)
					(with-subgoal sub (:args args)
						(let ((found (find-if #'(lambda (arg) (find-if #'(lambda (v) (var-eq-p v arg)) involved-variables)) (rest args))))
							(when found
								(subgoal-mark-as-blocked sub)))))))))

(defun type-check-const (const)
	(with-constant const (:name name :expr expr)
		(let* ((first-types (get-type expr *all-types*))
				 (res (select-simpler-types first-types)))
			(unless (one-elem-p res)
				(error 'type-invalid-error :text (tostring "could not determine type of const ~a" name)))
			(unless (same-types-p first-types res)
				(get-type expr res))
			(setf (constant-type const) (first res)))))

(defun type-check ()
	(do-definitions (:name name :types typs)
      (check-home-argument name typs))
	(dolist (const *consts*)
		(type-check-const const))
	(do-externs *externs* (:name name :ret-type ret-type :types types)
		(let ((extern (lookup-external-definition name)))
			(unless extern
				(error 'type-invalid-error :text (tostring "could not found external definition ~a" name)))
			(unless (eq ret-type (extern-ret-type extern))
				(error 'type-invalid-error :text
					(tostring "external function return types do not match: ~a and ~a"
						ret-type (extern-ret-type extern))))
			(dolist2 (t1 types) (t2 (extern-types extern))
				(unless (eq t1 t2)
					(error 'type-invalid-error :text
						(tostring "external function argument types do not match: ~a and ~a"
							t1 t2))))))
   (add-variable-head)
   (do-rules (:clause clause)
      (transform-clause-constants clause))
	(do-axioms (:clause clause)
      (transform-clause-constants clause))
   (do-all-rules (:head head :body body :clause clause)
      (type-check-clause head body clause nil))
   (do-all-axioms (:head head :body body :clause clause)
      (type-check-clause head body clause t)))
