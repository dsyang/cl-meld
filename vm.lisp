(in-package :cl-meld)

(defparameter *num-regs* 32)

(defmacro do-type-conversion (op base-type)
   `(case ,op
      ,@(mapcar #L`(,(format-keyword "~a" !1) ,(format-keyword "~a-~a" base-type !1))
                  '(equal not-equal lesser lesser-equal greater greater-equal plus mul div mod minus))))

(defun set-type-to-op (typ-args typ-ret op)
   (declare (ignore typ-ret))
   (case typ-args
      (:type-list-int (case op
                           (:equal :list-int-equal)))
      (:type-int (do-type-conversion op int))
      (:type-float (do-type-conversion op float))))

(defun make-process (name instrs) (list :process name instrs))
(defun process-name (proc) (second proc))
(defun process-instrs (proc) (third proc))

(defun make-move (from to) `(:move ,from ,to))
(defun move-to (mv) (third mv))
(defun move-from (mv) (second mv))

(defun make-move-nil (to) `(:move-nil ,to))
(defun move-nil-to (mv) (second mv))
(defun move-nil-p (mv) (tagged-p mv :move-nil))

(defun make-return () '(:return))

(defun instr-type (instr) (first instr))

(defun make-reg (n) `(:reg ,n))
(defun reg-p (r) (tagged-p r :reg))
(defun reg-num (r) (second r))

(defun make-reg-dot (reg field) `(:reg-dot ,reg ,field))
(defun reg-dot-reg (reg-dot) (second reg-dot))
(defun reg-dot-field (reg-dot) (third reg-dot))
(defun reg-dot-p (reg-dot) (tagged-p reg-dot :reg-dot))

(defun make-vm-nil () :nil)
(defun vm-nil-p (n) (eq n :nil))

(defun make-vm-not (place dest) `(:not ,place ,dest))
(defun vm-not-place (n) (second n))
(defun vm-not-dest (n) (third n))

(defun make-vm-test-nil (place dest) `(:test-nil ,place ,dest))
(defun vm-test-nil-place (tn) (second tn))
(defun vm-test-nil-dest (tn) (third tn))

(defun make-vm-cons (head tail dest) `(:cons ,head ,tail ,dest))
(defun vm-cons-head (c) (second c))
(defun vm-cons-tail (c) (third c))
(defun vm-cons-dest (c) (fourth c))
(defun vm-cons-p (c) (tagged-p c :cons))

(defun make-vm-head (con dest) `(:head ,con ,dest))
(defun vm-head-cons (h) (second h))
(defun vm-head-dest (h) (third h))
(defun vm-head-p (h) (tagged-p h :head))

(defun make-vm-tail (con dest) `(:tail ,con ,dest))
(defun vm-tail-cons (tail) (second tail))
(defun vm-tail-dest (tail) (third tail))
(defun vm-tail-p (tail) (tagged-p tail :tail))

(defun make-if (r instrs) (list :if r instrs))
(defun if-reg (i) (second i))
(defun if-instrs (i) (third i))

(defun make-vm-op (dst v1 op &optional v2) (list :op dst :to v1 op v2))
(defun vm-op-dest (st) (second st))
(defun vm-op-v1 (st) (fourth st))
(defun vm-op-op (st) (fifth st))
(defun vm-op-v2 (st) (sixth st))

(defun make-iterate (name matches instrs) (list :iterate name matches instrs))
(defun iterate-name (i) (second i))
(defun iterate-matches (i) (third i))
(defun iterate-instrs (i) (fourth i))
(defun match-left (m) (first m))
(defun match-right (m) (second m))

(defun make-vm-alloc (tuple reg) `(:alloc ,tuple ,reg))
(defun vm-alloc-tuple (alloc) (second alloc))
(defun vm-alloc-reg (alloc) (third alloc))

(defun make-vm-int (int) `(:int ,int))
(defun vm-int-p (int) (tagged-p int :int))
(defun vm-int-val (int) (second int))

(defun make-vm-float (flt) `(:float ,flt))
(defun vm-float-p (flt) (tagged-p flt :float))
(defun vm-float-val (flt) (second flt))

(defun make-vm-host-id () :host-id)
(defun vm-host-id-p (h) (eq h :host-id))

(defun make-send (from to &optional (time 0)) `(:send ,from ,to ,(make-vm-int time)))
(defun make-send-self (reg &optional (time 0)) (make-send reg reg time))
(defun send-from (send) (second send))
(defun send-to (send) (third send))
(defun send-time (send) (fourth send))

(defun make-vm-call (name dest args) `(:call ,name ,dest ,args))
(defun vm-call-name (call) (second call))
(defun vm-call-dest (call) (third call))
(defun vm-call-args (call) (fourth call))

(defun tuple-p (tp) (eq tp :tuple))
(defun match-p (m) (eq m :match))

(defun print-place (place)
   (cond
      ((vm-int-p place) (tostring "~a" (vm-int-val place)))
      ((vm-float-p place) (tostring "~a" (vm-float-val place)))
      ((vm-host-id-p place) "host-id")
      ((vm-nil-p place) "nil")
      ((reg-p place) (tostring "reg ~a" (reg-num place)))
      ((reg-dot-p place)
         (tostring "~a.~a"
            (if (match-p (reg-dot-reg place))
               "(match)"
               (reg-num (reg-dot-reg place)))
            (reg-dot-field place)))
      ((tuple-p place) "tuple")))
      
(defmacro generate-print-op (basic-typs basic-ops &body body)
   `(on-top-level
      (defun print-op (op)
         (case op
            ,@(loop for typ in basic-typs
                  appending (mapcar #L`(,(format-keyword "~a-~a" typ !1)
                                          ,(substitute #\Space #\- (tostring "~A ~A" typ !1))) basic-ops))
            (otherwise ,@body)))))
            
(generate-print-op (int float list-int) (equal not-equal lesser lesser-equal greater greater-equal plus minus mul div mod))

(defun print-instr-ls (instrs)
   (reduce #L(if !1 (concatenate 'string !1 (list #\Newline) (print-instr !2)) (print-instr !2))
                  instrs :initial-value nil))
                  
(defun print-match (m) (tostring "  ~a=~a~%" (print-place (first m)) (print-place (second m))))
(defun print-matches (matches)
   (if matches
      (reduce #L(concatenate 'string !1 (print-match !2)) matches :initial-value nil)
      ""))

(defun print-call-args (ls)
   (reduce #L(if (null !1) (print-place !2) (concatenate 'string !1 ", " (print-place !2))) ls :initial-value nil))

(defun print-instr (instr)
   (case (instr-type instr)
      (:return "RETURN")
      (:move-nil (tostring "MOVE-NIL ~a" (print-place (move-nil-to instr))))
      (:test-nil (tostring "TEST-NIL ~a TO ~a" (print-place (vm-test-nil-place instr)) (print-place (vm-test-nil-dest instr))))
      (:cons (tostring "CONS (~a::~a) TO ~a" (print-place (vm-cons-head instr))
               (print-place (vm-cons-tail instr)) (print-place (vm-cons-dest instr))))
      (:head (tostring "HEAD ~a TO ~a" (print-place (vm-head-cons instr)) (print-place (vm-head-dest instr))))
      (:tail (tostring "TAIL ~a TO ~a" (print-place (vm-tail-cons instr)) (print-place (vm-tail-dest instr))))
      (:call (tostring "CALL ~a TO ~a = (~a)" (vm-call-name instr) (reg-num (vm-call-dest instr))
                  (print-call-args (vm-call-args instr))))
      (:send (tostring "SEND ~a TO ~a IN ~ams" (print-place (send-from instr))
                  (print-place (send-to instr)) (print-place (send-time instr))))
      (:alloc (tostring "ALLOC ~a TO ~a" (vm-alloc-tuple instr) (print-place (vm-alloc-reg instr))))
      (:iterate (tostring "ITERATE OVER ~a MATCHING~%~a~a~%NEXT" (iterate-name instr)
                  (print-matches (iterate-matches instr)) (print-instr-ls (iterate-instrs instr)))) 
      (:op (tostring "OP ~a ~a ~a TO ~a" (print-place (vm-op-v1 instr)) (print-op (vm-op-op instr))
                                             (print-place (vm-op-v2 instr)) (print-place (vm-op-dest instr))))
      (:not (tostring "NOT ~a TO ~a" (print-place (vm-not-place instr)) (print-place (vm-not-dest instr))))
      (:if (tostring "IF (~a) THEN~%~a~%ENDIF" (print-place (if-reg instr)) (print-instr-ls (if-instrs instr))))
      (:move (tostring "MOVE ~a TO ~a" (print-place (move-from instr)) (print-place (move-to instr))))))

(defun print-vm (processls)
   (with-output-to-string (str)
      (do-processes processls (:name name :instrs instrs)
         (format str "PROCESS ~a:~%" name)
         (dolist (instr instrs)
            (format str "~a~%" (print-instr instr)))
         (format str "~%"))))