
(in-package :cl-meld)

(define-condition compile-invalid-error (error)
   ((text :initarg :text :reader text)))

(defmacro with-memory-stream (s &body body)
   `(let ((,s (make-in-memory-output-stream)))
      ,@body
      s))

(defun output-external-functions (code s)
   (format s "#include \"extern_functions.h\"~%Register (*extern_functs[])() = {")
   (do-externs code (:name name :id id)
      (format s "~a(Register (*)())&~a" (if (> id 0) ", " "") name))
   (format s "};~%")
   (format s "int extern_functs_args[] = {")
   (do-externs code (:types typs)
      (format s "~a," (length typs)))
   (format s "};~%"))
   
(defun output-tuple-names (code s)
   (format s "char *tuple_names[] = {")
   (do-definitions code (:name name :id id)
      (format s "~a\"~a\"" (if (> id 0) ", " "") name))
   (format s "};~%"))
   
(defun output-int (int)
   (loop for i upto 3
      collect (ldb (byte 8 (* i 8)) int)))
(defun output-float (flt) (output-int (encode-float32 flt)))

(defun output-value (val)
   (cond
      ((vm-int-p val) (list #b000001 (output-int (vm-int-val val))))
      ((vm-float-p val) (list #b000000 (output-float (vm-float-val val))))
      ((vm-host-id-p val) (list #b000011))
      ((tuple-p val) (list #b011111))
      ((reg-p val) (list (logior #b100000 (logand #b011111 (reg-num val)))))
      ((reg-dot-p val) (list #b000010 (list (reg-dot-field val) (reg-num (reg-dot-reg val)))))
      (t (error 'compile-invalid-error :text "invalid expression value"))))

(defmacro add-byte (b vec) `(vector-push-extend ,b ,vec))
(defun add-bytes (vec &rest bs)
   (dolist (b bs) (add-byte b vec)))

(defmacro do-vm-values (vec vals &rest instrs)
   (labels ((map-value (i) (case i (1 'first-value) (2 'second-value)))
            (map-value-bytes (i) (case i (1 'first-value-bytes) (2 'second-value-bytes))))
      (let* ((i 0)
             (vals-code (mapcar #'(lambda (val) `(output-value ,val)) vals))
             (instrs-code `(progn ,@(mapcar #'(lambda (instr) `(add-byte ,instr ,vec)) instrs)
                              ,@(loop for i from 1 upto (length vals)
                                    collect `(dolist (bt ,(map-value-bytes i))
                                                (add-byte bt ,vec))))))
         (reduce #'(lambda (all val)
                     (incf i)
                     `(let* ((value ,val)
                           (,(map-value i) (first value))
                           (,(map-value-bytes i) (second value)))
                              ,all))
                  vals-code :initial-value instrs-code :from-end nil))))
            
(defun get-op-byte (op)
   (case op
      (:float-not-equal #b00000)
      (:int-not-equal #b00001)
      (:float-equal #b00010)
      (:int-equal #b00011)
      (:float-lesser #b00100)
      (:int-lesser #b00101)
      (:float-lesser-equal #b00110)
      (:int-lesser-equal #b00111)
      (:float-greater #b01000)
      (:int-greater #b01001)
      (:float-greater-equal #b01010)
      (:int-greater-equal #b01011)
      (:float-mod #b01100)
      (:int-mod #b01101)
      (:float-plus #b01110)
      (:int-plus #b01111)
      (:float-minus #b10000)
      (:int-minus #b10001)
      (:float-mul #b10010)
      (:int-mul #b10011)
      (:float-div #b10100)
      (:int-div #b10101)))
      
(defun reg-to-byte (reg) (reg-num reg))

(defun lookup-tuple-id (ast tuple)
   (do-definitions ast (:id id :name name)
      (if (equal name tuple) (return-from lookup-tuple-id id))))
      
(defun lookup-extern-id (ast extern)
   (do-externs ast (:id id :name name)
      (if (equal name extern) (return-from lookup-extern-id id))))
      
(defun output-match (match vec fs)
   (let* ((val (output-value (match-right match)))
          (val-byte (first val))
          (val-bytes (second val))
          (reg-dot (match-left match))
          (field (reg-dot-field reg-dot)))
      (add-byte field vec)
      (add-byte (logior fs val-byte) vec)
      (dolist (by val-bytes)
         (add-byte by vec))))
      
(defun output-matches (matches vec)
   (cond
      ((null matches)
         (add-byte #b00000000 vec)
         (add-byte #b11000000 vec))
      ((one-elem-p matches) (output-match (first matches) vec #b01000000))
      (t (output-match (first matches) vec #b00000000)
         (output-matches (rest matches) vec))))

(defmacro jumps-here (vec)
   `(progn
      (add-byte #b0 ,vec)
      (add-byte #b0 ,vec)))
      
(defmacro write-jump (vec jump-many &body body)
   (with-gensyms (pos len ls)
      `(let ((,pos (length ,vec)))
          ,@body
          (let* ((,len (- (length ,vec) ,pos))
                 (,ls (output-int ,len)))
            (setf (aref ,vec (+ ,pos ,jump-many)) (first ,ls)
                  (aref ,vec (+ 1 ,jump-many ,pos)) (second ,ls))))))

(defun output-instr (ast instr vec)
   (case (instr-type instr)
      (:return (add-byte #x0 vec))
      (:set (let ((op (get-op-byte (set-op instr)))
                  (reg-byte (reg-to-byte (set-destiny instr))))
               (do-vm-values vec ((set-v1 instr) (set-v2 instr))
                           (logior #b11000000 (logand #b00111111 first-value))
                           (logior (logand #b11111100 (ash second-value 2))
                                   (logand #b00000011 (ash reg-byte -3)))
                           (logior (logand #b11100000 (ash reg-byte 5)) op))))
      (:alloc (let ((tuple-id (lookup-tuple-id ast (vm-alloc-tuple instr))))
                  (do-vm-values vec ((vm-alloc-reg instr))
                     (logior #b01000000 (logand #b00011111 (ash tuple-id -2)))
                     (logior (logand #b11000000 (ash tuple-id 6)) first-value))))
      (:send (do-vm-values vec ((send-time instr))
                (logior #b00001000 (logand #b00000011 (ash (reg-num (send-from instr)) -3)))
                (logior (logand #b11100000 (ash (reg-num (send-from instr)) 5))
                        (reg-num (send-to instr)))
               first-value))
      (:call (let ((extern-id (lookup-extern-id ast (vm-call-name instr)))
                   (args (vm-call-args instr)))
               (add-byte (logior #b00100000 (ash extern-id -4)) vec)
               (add-byte (logior (logand #b11110000 (ash extern-id 4))
                                 (reg-to-byte (vm-call-dest instr))) vec)
               ;(add-byte (logand #b11111000 (ash (length args) 3)) vec)
               (dolist (arg args)
                  (let ((res (output-value arg)))
                     (add-byte (first res) vec)
                     (dolist (b (second res)) (add-byte b vec))))))
      (:if (let ((reg-b (reg-to-byte (if-reg instr))))
             (write-jump vec 1
               (add-byte (logior #b01100000 reg-b) vec)
               (jumps-here vec)
               (output-instrs (if-instrs instr) vec ast))))
      (:iterate (write-jump vec 2
                  (add-byte #b10100000 vec)
                  (add-byte (lookup-tuple-id ast (iterate-name instr)) vec)
                  (jumps-here vec)
                  (output-matches (iterate-matches instr) vec)
                  (output-instrs (iterate-instrs instr) vec ast)
                  (add-byte #b00000001 vec)))
      (:move (do-vm-values vec ((move-from instr) (move-to instr))
                (logior #b00110000 (logand #b00001111 (ash first-value -2)))
                (logior (logand #b11000000 (ash first-value 6)) second-value)))))
                
(defun output-instrs (ls vec ast)
   (dolist (instr ls)
      (output-instr ast instr vec)))
                             
(defun output-processes (ast code)
   (do-processes code (:instrs instrs :operation collect)
      (letret (vec (create-bin-array))
         (output-instrs instrs vec ast))))

(defun output-arg-type (typ vec)
   (add-byte
      (case typ
         (:type-node #b0010)
         (:type-int #b0000)
         (:type-float #b0001))
      vec))
   
(defun output-aggregate-type (agg typ)
   (case agg
      (:first #b0001)
      (:min (case typ
               (:type-int #b0011)
               (:type-float #b0110)))
      (:max (case typ
               (:type-int #b0010)
               (:type-float #b0101)))
      (:sum (case typ
               (:type-int #b0100)
               (:type-float #b0111)))))
               
(defun output-aggregate (types)
   (let ((agg (find-if #'aggregate-p types)))
      (if agg
         (let ((pos (position-if #'aggregate-p types))
               (agg (aggregate-agg agg))
               (typ (aggregate-type agg)))
            (logior (logand #b11110000 (ash (output-aggregate-type agg typ) 4))
                    (logand #b00001111 pos)))
         #b00000000)))
         
(defun output-properties (types)
   (let ((agg (find-if #'aggregate-p types)))
      (if agg
         #b00000001
         #b00000000)))
      
(defun output-descriptors (ast)
   (do-definitions ast (:types types :operation collect)
      (letret (vec (create-bin-array))
         (add-bytes vec #b0 #b0) ; code offset
         (add-byte (output-properties types) vec) ; property byte
         (add-byte (output-aggregate types) vec) ; aggregate byte
         (add-byte #b0 vec) ; strat order
         (add-byte (length types) vec) ; number of args
         (add-byte #b0 vec) ; delta stuff
         (dolist (typ (definition-arg-types types))
            (output-arg-type typ vec)))))
            
(defun write-hexa (stream int) (format stream "0x~X," int))
(declaim (inline write-hexa))

(defun do-output-code (ast code stream)
   (format stream "const unsigned char meld_prog[] = {")
   (write-hexa stream (length (definitions ast)))
   (let* ((processes (output-processes ast code))
          (process-lens (mapcar #'length processes)) 
          (descriptors (output-descriptors ast))
          (desc-lens (mapcar #'length descriptors))
          (desc-len (reduce #'+ desc-lens :initial-value 0))
          (initial-offset (+ 1 (length (definitions ast)))))
      (dolist (off (addify desc-lens initial-offset))
         (write-hexa stream off))
      (loop for desc in descriptors ; update code offsets
            for off in (addify process-lens (+ initial-offset desc-len))
            for intls = (output-int off)
            do (setf (aref desc 0) (first intls)
                     (aref desc 1) (second intls)))
      (dolist (vec (append descriptors processes))
         (loop for b being the elements of vec
               do (write-hexa stream b))))
   (format stream "};~%")
   (format stream "const unsigned int size_meld_prog = sizeof(meld_prog);~%~%"))
   
(defun output-code (ast code file)
   (with-open-file (stream file
                     :direction :output
                     :if-exists :supersede
                     :if-does-not-exist :create)
      (output-external-functions ast stream)
      (output-tuple-names ast stream)
      (do-output-code ast code stream)
      (format stream "/*~%~a*/~%" (print-vm code))))