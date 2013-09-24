This is a compiler for the Meld programming language written in Common Lisp.

Please see this paper for more information on Meld:
A Language for Large Ensembles of Independently Executing Nodes:
	http://www.cs.cmu.edu/~mpa/papers/ashley-rollman-iclp09.pdf

Installation:
=============

## Mac:

1. Install sbcl (Steel Bank Common Lisp)[http://www.sbcl.org/]

```
brew install sbcl
```

2. Use quicklisp to install the common lisp dependencies:
  - first start the sbcl REPL and load quicklisp
  ``` sbcl --load quicklisp.lisp ```
  - install the required libraries

```lisp
    ;; Add quicklisp to your sbcl init file so you don't have to --load it all the time
	* (ql:add-to-init-file)
	;; install the required packages
	* (ql:quickload "cl-ppcre")
	* (ql:quickload "yacc")
	* (ql:quickload "cl-lex")
	* (ql:quickload "arnesi")
	* (ql:quickload "alexandria")
	* (ql:quickload "flexi-streams")
	* (ql:quickload "ieee-floats")
```

3. Load and run the compiler:
```lisp
    * (load "load")

    ;; Run this function to compile a file
	* (cl-meld:meld-compile "path-to-file.meld" "path-to-output-file")

    ;; If all goes well, you should see "All done. T"
```


4. (Optional) Create a binary to run the compiler:

We can easily create an executable of the compiler with SBCL:

```lisp
    * (load "main")
	* (sb-ext:save-lisp-and-die "cl-meld" :executable t :toplevel 'main)
```

The executable takes the input .meld filename as it's first argument and the output bytecode filename as it's second argument

```
    $> ./cl-meld "mergesort.meld" "mergesort"
```
