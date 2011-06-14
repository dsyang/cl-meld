(in-package :cl-meld)

(define-condition expr-invalid-error (error)
   ((text :initarg :text :reader text)))

(defmacro define-makes (&rest symbs)
   `(on-top-level
      ,@(mapcar #'(lambda (sym)
         `(defun ,(intern (concatenate 'string "MAKE-" (symbol-name sym))) (a b c)
               (declare (ignore b))
               (list ,sym a c)))
            symbs)))

(define-makes :plus :minus :mul :mod :div
      :lesser :lesser-equal :greater :greater-equal
      :equal :assign :not-equal)
      
(defun make-call (name args) `(:call ,name ,args))
(defun call-name (call) (second call))
(defun call-args (call) (third call))
(defun call-p (call) (tagged-p call :call))

(defun make-cons (h ts) `(:cons ,h ,ts))
(defun cons-p (c) (tagged-p c :cons))
(defun cons-head (c) (second c))
(defun cons-tail (c) (third c))
(defun make-head (c) `(:head ,c))
(defun head-list (c) (second c))
(defun make-tail (c) `(:tail ,c))
(defun tail-list (c) (second c))
(defun tail-p (c) (tagged-p c :tail))
(defun head-p (c) (tagged-p c :head))

(defun make-true () '(:true))
(defun make-false () '(:false))
(defun true-p (true) (tagged-p true :true))
(defun false-p (false) (tagged-p false :false))

(defun make-not (expr) `(:not ,expr))
(defun not-expr (not) (second not))
(defun not-p (expr) (tagged-p expr :not))

(defun make-test-nil (expr) `(:test-nil ,expr))
(defun test-nil-expr (tn) (second tn))
(defun test-nil-p (tn) (tagged-p tn :test-nil))

(defun make-nil () (list :nil))
(defun nil-p (n) (tagged-p n :nil))

(defun make-addr (num) (list :addr num :type-addr))
(defun addr-num (addr) (second addr))
(defun addr-p (addr) (tagged-p addr :addr))
(defun set-addr-num (addr new-num)
   (setf (second addr) new-num))
(defsetf addr-num set-addr-num)

(defun option-has-tag-p (opts opt) (some #L(tagged-p !1 opt) opts))

(defun make-clause (perm conc &rest options) `(:clause ,perm ,conc ,options))
(defun clause-head (clause) (third clause))
(defun clause-body (clause) (second clause))
(defun set-clause-body (clause new-body)
   (setf (second clause) new-body))
(defsetf clause-body set-clause-body)

(defun clause-options (clause) (fourth clause))
(defun clause-add-option (clause opt) (push opt (fourth clause))) 
(defun clause-has-tagged-option-p (clause opt) (option-has-tag-p (clause-options clause) opt))
(defun clause-get-tagged-option (clause opt)
   (let ((res (find-if #L(tagged-p !1 opt) (clause-options clause))))
      (when res
         (rest res))))
(defun clause-get-remote-dest (clause)
   (first (clause-get-tagged-option clause :route)))
(defun clause-is-remote-p (clause) (clause-has-tagged-option-p clause :route))
(defun clause-has-delete-p (clause) (clause-has-tagged-option-p clause :delete))
(defun clause-get-delete (clause) (clause-get-tagged-option clause :delete))
   
(defun head-host-node (head-list)
   (first (subgoal-args (first head-list))))
(defun clause-host-node (clause)
   (head-host-node (clause-head clause)))

(defun make-colocated (h1 h2)
   (list :colocated h1 h2))
(defun colocated-first (c) (second c))
(defun colocated-second (c) (third c))
      
(defun make-subgoal (name args)
   (if (equal name "colocated")
       (cond
          ((= (length args) 2) (make-constraint (make-colocated (first args) (second args))))
          (t (error 'expr-invalid-error "Colocated expression must have two arguments")))
       (list :subgoal name args)))
(defun make-var (var &optional typ) `(:var ,(if (stringp var) (str->sym var) var) ,@(if typ `(,typ) nil)))

(defun make-definition (name typs &rest options) `(:definition ,name ,typs ,options))
(defun definition-p (def) (tagged-p def :definition))
(defun definition-name (def) (second def))
(defun definition-types (def) (third def))
(defun set-definition-types (def new-types)
   (setf (third def) new-types))
(defsetf definition-types set-definition-types)
(defun definition-options (def) (fourth def))
(defun definition-add-option (def opt) (push opt (fourth def)))
(defun definition-has-option-p (def opt)
   (has-elem-p (definition-options def) opt))
(defun definition-has-tagged-option-p (def opt)
   (some #L(tagged-p !1 opt) (definition-options def)))
(defun definition-get-tagged-option (def opt)
   (let ((res (find-if #L(tagged-p !1 opt) (definition-options def))))
      (when res
         (second res))))

(defun is-init-p (def)
   (definition-has-option-p def :init-tuple))
(defun is-route-p (def)
   (definition-has-option-p def :route))
(defun is-reverse-route-p (def)
   (definition-has-tagged-option-p def :reverse-route))
(defun find-init-predicate (defs) (find-if #'is-init-p defs))
(defun find-init-predicate-name (defs)
   (definition-name (find-init-predicate defs)))
(defun get-routes (code)
   (filter #'is-route-p (definitions code)))
(defun get-route-names (code)
   (mapcar #'definition-name (get-routes code)))
   
(defun subgoal-matches-def-p (sub def)
   (equal (subgoal-name sub) (definition-name def)))
(defun subgoal-match-p (sub1 sub2)
   (equal (subgoal-name sub1) (subgoal-name sub2)))

(defun make-aggregate (agg typ mod) `(:aggregate ,agg ,typ ,mod))
(defun aggregate-p (agg) (tagged-p agg :aggregate))
(defun aggregate-agg (agg) (second agg))
(defun aggregate-type (agg) (third agg))
(defun aggregate-mod (agg) (fourth agg))
(defun definition-aggregate (def)
   (with-definition def (:types typs) (find-if #'aggregate-p typs)))
(defun arg-type (arg)
   (if (aggregate-p arg)
       (aggregate-type arg)
       arg))
(defun definition-arg-types (typs) (mapcar #'arg-type typs))

(defun definition-aggregate-p (def)
   (with-definition def (:types typs)
      (some #'aggregate-p typs)))

(defun make-extern (name ret-type types) `(:extern ,name ,ret-type ,types))
(defun extern-p (ext) (tagged-p ext :extern))
(defun extern-name (ext) (second ext))
(defun extern-ret-type (ext) (third ext))
(defun extern-types (ext) (fourth ext))

(defun make-constraint (expr &optional (priority 0)) (list :constraint expr priority))
(defun constraint-p (ls) (tagged-p ls :constraint))
(defun constraint-expr (ls) (second ls))
(defun constraint-priority (ls) (third ls))

(defmacro define-ops (&rest symbs)
   `(on-top-level
      ,@(mapcar #'(lambda (sy)
            `(defun ,(intern (concatenate 'string (symbol-name sy) "-P")) (val)
                  (tagged-p val ,sy)))
         symbs)))
         
(define-ops :int :float :var :plus :minus :mul :div :mod
            :equal :not-equal
            :lesser :lesser-equal :greater :greater-equal
            :convert-float :world :colocated)

(defun const-p (s)
   (or (int-p s) (float-p s) (call-p s)
      (cons-p s) (nil-p s) (addr-p s)))
            
(defun op-op (val) (tagged-tag val))
(defun op-op1 (val) (second val))
(defun op-op2 (val) (third val))

(defun op-p (val)
   (any (plus-p minus-p mul-p div-p mod-p not-equal-p equal-p lesser-p lesser-equal-p greater-p greater-equal-p) val))

(defun int-val (val) (second val))
(defun make-int (int &optional typ)
   (if typ
      `(:int ,int ,typ)
      `(:int ,int)))
(defun make-forced-int (int) (make-int int :type-int))

(defun float-val (val) (second val))
(defun make-float (flt) `(:float ,flt :type-float))

(defun make-host-id () '(:host-id :type-addr))
(defun host-id-p (h) (tagged-p h :host-id))

(defun make-convert-float (expr) `(:convert-float ,expr))
(defun convert-float-expr (flt) (second flt))

(defun make-world () (list :world))

(defun var-name (val) (second val))
(defun var-eq-p (v1 v2) (equal (var-name v1) (var-name v2)))

(defun typed-var-p (var) (and (= (length var) 3)))
(defun single-typed-var-p (var) (and (typed-var-p var) (one-elem-p (third var))))
(defun typed-op-p (op) (= (length op) 4))
(defun typed-int-p (i) (= (length i) 3))

;;;; AST

(defun make-ast (defs clauses &optional nodes)
   `(:definitions ,defs :clauses ,clauses :nodes ,nodes))
            
(defun all-definitions (code) (second code))
(defun definitions (code) (filter #'definition-p (all-definitions code)))
(defun set-definitions (code new-defs)
   (setf (second code) new-defs))
(defsetf definitions set-definitions)
(defsetf all-definitions set-definitions)

(defun externs (code) (filter #'extern-p (all-definitions code)))
  
(defun clauses (code) (fourth code))
(defun set-clauses (code new-clauses)
   (setf (fourth code) new-clauses))
(defsetf clauses set-clauses)

(defun defined-nodes (code) (sixth code))
(defun set-defined-nodes (code new-nodes)
   (setf (sixth code) new-nodes))
(defsetf defined-nodes set-defined-nodes)

;;;; ASSIGNMENTS

(defun assignment-p (ls) (tagged-p ls :assign))
(defun assignment-var (ls) (second ls))
(defun assignment-expr (ls) (third ls))

;;;; SUBGOALS

(defun subgoal-p (ls) (tagged-p ls :subgoal))
(defun subgoal-name (subgoal) (second subgoal))
(defun subgoal-args (subgoal) (third subgoal))
(defun set-subgoal-args (subgoal new-args)
   (setf (third subgoal) new-args))
(defsetf subgoal-args set-subgoal-args)

(defun get-assignments (body) (filter #'assignment-p body))
(defun get-assignment-vars (assignments) (mapcar #'assignment-var assignments))
(defun get-subgoals (code) (filter #'subgoal-p code))
(defun get-constraints (code) (remove-if-not #'constraint-p code))

(defun expr-type (expr)
   (cond
      ((or (nil-p expr) (host-id-p expr)) (second expr))
      ((or (var-p expr) (int-p expr) (float-p expr) (addr-p expr) (tail-p expr)
           (head-p expr) (not-p expr) (test-nil-p expr)
           (convert-float-p expr))
         (third expr))
      ((or (op-p expr) (call-p expr) (cons-p expr))
         (fourth expr))
      (t (error 'type-invalid-error :text (tostring "Cannot deduce type of expression ~a" expr)))))

(defun lookup-definition-types (defs pred)
   (when-let ((def (lookup-definition defs pred)))
      (definition-types def)))
      
(defun lookup-definition (defs pred)
   (find-if #L(string-equal pred (definition-name !1)) (filter #'definition-p defs)))

(defun lookup-extern (defs name)
   (find-if #L(string-equal name (extern-name !1)) (filter #'extern-p defs)))

(defparameter *number-types* '(:type-int :type-float))
(defparameter *list-number-types* '(:type-list-int :type-list-float))
(defparameter *list-types* `(,@*list-number-types* :type-list-addr))
(defparameter *all-types* `(,@*number-types* :type-bool :type-addr ,@*list-types*))

(defmacro deftype-p (&rest types)
   `(on-top-level
         ,@(mapcar #'(lambda (x) `(defun ,(format-symbol t "TYPE-~A-P" (symbol-name x)) (ty)
                                       (eq ,(format-symbol "KEYWORD" "TYPE-~A" (symbol-name x)) ty)))
                  types)))

(deftype-p int addr bool float list-int list-float list-addr)

(defun has-constraints (subgoals) (some #'constraint-p subgoals))
(defun has-assignments (subgoals) (some #'assignment-p subgoals))
   
(defun op-to-string (op)
   (case op
      (:plus "+")
      (:minus "-")
      (:mul "*")
      (:div "/")
      (:mod "%")
      (:equal "=")
      (:not-equal "!=")
      (:lesser "<")
      (:lesser-equal "<=")
      (:greater ">")
      (:greater-equal ">=")))
      
(defmacro eq-or (sym &rest symbols)
   `(or ,@(mapcar #'(lambda (s) `(eq ,sym ,s)) symbols)))
   
(defun eq-arith-p (sym) (eq-or sym :plus :minus :mul :div :mod))
(defun eq-cmp-p (sym) (eq-or sym :equal :not-equal :lesser :lesser-equal :greater :greater-equal))
      
(defun type-operands (op &optional forced-types)
   (cond
      ((eq-arith-p op)
         (if forced-types
            (intersection forced-types *number-types*)
            *number-types*))
      ((eq-cmp-p op)
         (if (or forced-types
                 (not (has-elem-p forced-types :type-bool)))
            `(,@*number-types* :type-addr :type-bool ,@*list-types*)))))

(defun type-op (op &optional forced-types)
   (cond
      ((eq-arith-p op)
         (if forced-types
            (intersection *number-types* forced-types)
            '*number-types*))
      ((eq-cmp-p op)
         (if forced-types
            (intersection '(:type-bool) forced-types)
            '(:type-bool)))))
            
(defun type-oper-op (op forced-types)
   (cond
      ((eq-arith-p op)
         (intersection *number-types* forced-types))
      ((eq-cmp-p op) '(:type-bool))))

(defun iterate-expr (fn expr)
   (unless expr
      (return-from iterate-expr nil))
   (let ((ls (list)))
      (labels ((aux (expr)
                  (let ((val (funcall fn expr)))
                     (cond
                        ((eq val :stop) (return-from aux))
                        (val
                           (push val ls))))
                  (cond
                     ((subgoal-p expr) (dolist (arg (subgoal-args expr)) (aux arg)))
                     ((constraint-p expr) (aux (constraint-expr expr)))
                     ((assignment-p expr)
                        (aux (assignment-var expr))
                        (aux (assignment-expr expr)))
                     ((var-p expr) nil)
                     ((int-p expr) nil)
                     ((float-p expr) nil)
                     ((host-id-p expr) nil)
                     ((nil-p expr) nil)
                     ((world-p expr) nil)
                     ((addr-p expr) nil)
                     ((call-p expr) (dolist (arg (call-args expr)) (aux arg)))
                     ((cons-p expr)
                        (aux (cons-head expr))
                        (aux (cons-tail expr)))
                     ((head-p expr) (aux (head-list expr)))
                     ((tail-p expr) (aux (tail-list expr)))
                     ((not-p expr) (aux (not-expr expr)))
                     ((test-nil-p expr) (aux (test-nil-expr expr)))
                     ((convert-float-p expr) (aux (convert-float-expr expr)))
                     ((colocated-p expr)
                        (aux (colocated-first expr))
                        (aux (colocated-second expr)))
                     ((op-p expr)
                        (aux (op-op1 expr))
                        (aux (op-op2 expr)))
                     ((and (listp expr)
                           (not (symbolp (first expr)))
                           (listp (first expr)))
                        (dolist (el expr)
                           (aux el)))
                     (t (error 'expr-invalid-error :text (tostring "Invalid expression: ~a" expr))))))
            (aux expr)
            ls)))
      
(defun all-variables (expr)
   (let ((vars (iterate-expr #'(lambda (x)
                                 (cond
                                    ((var-p x) x))) expr)))
      (remove-duplicates vars :test #'equal)))
      
(defun all-variable-names (expr) (mapcar #'var-name (all-variables expr)))

(defparameter *var-counter* 0)
(defun generate-random-var () (make-var (with-output-to-string (a) (format a "MANGLEDVAR~a" (incf *var-counter*)))))

(defun valid-assignment-p (vars) #'(lambda (a) (tree-subsetp (all-variable-names (assignment-expr a)) vars)))
(defun select-valid-assignments (body subgoals &optional (base-vars nil))
   (loop with vars = (union base-vars (all-variable-names subgoals))
         with ass = (get-assignments body)
         with ret = nil
         for (next-assignments . new-ass) = (split (valid-assignment-p vars) ass)
         while next-assignments
         do (setf ass new-ass)
         do (push-all next-assignments ret)
         do (push-all (mapcar #L(var-name (assignment-var !1)) next-assignments) vars)
         finally (return ret)))

(defun unneeded-assignment-p (body)
   #'(lambda (a)
         (let ((var-name (var-name (assignment-var a)))
               (vars (all-variable-names (remove-tree a body))))
            (not (has-elem-p vars var-name)))))
(defun remove-unneeded-assignments (body &optional head)
   (loop with ass = (get-assignments body)
         for (next-unneeded . next-ass) = (split (unneeded-assignment-p (append body head)) ass)
         while next-unneeded
         do (setf ass next-ass
                  body (remove-all body next-unneeded))
         finally (return body)))
         
(defun is-fact-p (code pred-name)
   "Given a predicate name tells you if it is a fact in the program."
   (do-clauses (clauses code) (:body body)
      (if (some #'(lambda (sub) (equal (subgoal-name sub) pred-name)) (get-subgoals body))
         (return-from is-fact-p t)))
   nil)

(defun find-constraints (body fn)
   (filter #L(and (constraint-p !1) (funcall fn (constraint-expr !1))) body))
   
(defun constraint-by-var1 (var-name expr) (var-eq-p var-name (op-op1 expr)))
(defun constraint-by-var2 (var-name expr) (var-eq-p var-name (op-op2 expr)))
