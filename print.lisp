
(defun print-args (args)
   (format t "[")
   (do-args args (typ val id)
      (if (> id 1)
         (format t " "))
      (format t "~A(~A)" typ val))
   (format t "]"))
   
(defun print-subgoals (subgoals)
   (do-subgoals subgoals (name args)
      (format t " ~A" name)
      (print-args args)))
      
(defun print-program (code)
   (format t "I found the following definitions:~%")
   (do-definitions code (name typs)
      (format t "~A ~A~%" name typs))
   (format t "I found the following clauses:~%")
   (do-clauses code (head body id)
      (format t "Clause ~A:" id)
      (print-subgoals head)
      (format t " :-")
      (print-subgoals body)
      (format t "~%")))