(defpackage #:meld-asd
 (:use :cl :asdf))

(in-package :meld-asd)

(defsystem cl-meld
 :name "meld"
 :version "0.0"
 :author "Flavio Cruz"
 :description "Meld compiler"
 :depends-on (:cl-lex :yacc :arnesi :alexandria :unit-test :flexi-streams :ieee-floats)
 :components ((:file "parser"
		 						:depends-on ("package"
		 						             "macros"
		 						             "manip"))
		 			(:file "util"
		 			         :depends-on ("package"
		 			                       "macros"))
		 			(:file "manip"
		 			         :depends-on ("package"
		 			                      "util"
		 			                      "macros"))
		 			(:file "macros"
		 			         :depends-on ("package"))
		 			(:file "typecheck"
		 			         :depends-on ("package"
		 			                      "manip"
		 			                      "macros"))
		 			(:file "localize"
		 			         :depends-on ("package"
		 			                      "manip"
		 			                      "macros"))
		 			(:file "vm"
		 			         :depends-on ("util"
		 			                      "macros"
		                               "manip"))
		 			(:file "compile"
		 			         :depends-on ("package"
		 			                      "manip"
		 			                      "macros"
		 			                      "vm"))
		 			(:file "meld"
		 			         :depends-on ("parser"
		 			                      "localize"
		 			                      "compile"
		 			                      "models/parallel"
		 			                      "output"))
		 			(:file "models/base"
		 			         :depends-on ("manip"
		 			                      "macros"
		 			                      "util"))
		 			(:file "models/parallel"
		 			         :depends-on ("models/base"))
		 			(:file "output"
		 			         :depends-on ("manip"
		 			                      "util"
		 			                      "compile"
		 			                      "vm"))
		 			(:file "print"
		 			         :depends-on ("package"
		 			                      "manip"))
	 						(:file "package")))

