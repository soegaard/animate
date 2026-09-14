#lang racket/base

;;;
;;; Mathematical Notation and Source Ranges
;;;
;; Converts held syntax to TeX and records semantic source ownership. Formatting never
;; launches TeX or normalizes the mathematical state.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "validation.rkt"
  racket/list
  (only-in racket/match match)
  (only-in racket/string string-join)
  "datum.rkt"
  "model.rkt")

;; Exports
(provide
  math->tex datum->tex format-math-source (struct-out math-source)
  (struct-out math-source-span) math->string)

;;;
;;; Data Representation
;;;
(struct math-source-span (start end path role)
  #:transparent
  #:guard
  (lambda (start end path role who)
    (unless (and
              (exact-nonnegative-integer? start)
              (exact-nonnegative-integer? end)
              (< start end))
      (raise-arguments-error who
        "a nonempty half-open character range"
        "start"
        start
        "end"
        end))
    (values start end (check-path who path) (check-symbol who role))))
;; math-source-span is an immutable record. Its fields have the following roles.
;;  - start  exact-nonnegative-integer?  inclusive character offset
;;  - end  exact-positive-integer?  exclusive character offset
;;  - path  operand-path?  mathematical owner location
;;  - role  symbol?  expression, atom, relation, or operator role
(struct math-source (text spans)
  #:transparent
  #:guard
  (lambda (text spans who)
    (unless (string? text) (raise-argument-error who "string?" text))
    (check-list-of who spans math-source-span? "list of source spans")
    (for ([span (in-list spans)])
      (unless (<= (math-source-span-end span) (string-length text))
        (raise-arguments-error who "source span extends past the source text" "span" span)))
    (values (string->immutable-string text) spans)))
;; math-source is an immutable record. Its fields have the following roles.
;;  - text  immutable-string?  one complete TeX formula
;;  - spans  (listof math-source-span?)  start-ordered possibly nested semantic ranges

;;;
;;; Notation Policies
;;;
; greek : immutable-hash?
;;   Maps explicitly supported mathematical names to TeX commands.
(define greek
  (hash 'α "\\alpha" 'β "\\beta" 'γ "\\gamma" 'δ "\\delta" 'Δ "\\Delta" 'θ "\\theta" 'λ "\\lambda" 'μ "\\mu" 'π "\\pi" 'σ "\\sigma" 'φ "\\phi" 'ω "\\omega" '@pi "\\pi" '@e "\\mathrm{e}" '@i "\\mathrm{i}"))

; escape : any/c -> string?
;;   Escapes literal variable characters before inserting them into TeX.
(define (escape s)
  (string-join
    (for/list ([c (in-string s)])
      (case c
        [(#\_) "\\_"]
        [(#\%) "\\%"]
        [(#\&) "\\&"]
        [(#\#) "\\#"]
        [(#\{) "\\{"]
        [(#\}) "\\}"]
        [(#\$) "\\$"]
        [(#\\) "\\backslash{}"]
        [(#\^) "\\textasciicircum{}"]
        [(#\~) "\\textasciitilde{}"]
        [else (string c)]))
    ""))

; variable-tex : any/c -> string?
;;   Formats one variable or recognized mathematical constant.
(define (variable-tex v)
  (hash-ref greek v
    (lambda ()
      (define s (symbol->string v))
      (if (regexp-match? #px"^[A-Za-z]$" s) s (format "\\mathrm{~a}" (escape s))))))

; precedence : math-datum? -> exact-nonnegative-integer?
;;   Assigns presentation precedence without changing mathematical syntax.
(define (precedence d)
  (case (head d) [(or and) 0] [(= < > <= >=) 1] [(+ -) 2] [(*) 3] [(expt) 4] [else 5]))

;;;
;;; Held Formula Source
;;;
; format-math-source : (or/c math? math-datum?) [#:multiplication symbol?] ->
;   math-source?
;;   Formats one complete formula and retains half-open source spans for its
;;   occurrences.
(define (format-math-source datum #:multiplication [multiplication 'school])
  (define d (if (math? datum) (math-datum datum) datum))
  (check-datum 'format-math-source d)
  (unless (memq multiplication '(school explicit))
    (raise-argument-error 'format-math-source "'school or 'explicit" multiplication))
  (define output (open-output-string))
  (define position 0)
  (define spans '())
  (define (emit s) (display s output) (set! position (+ position (string-length s))))
  (define (marked p role thunk)
    (define start position)
    (thunk)
    (when (> position start)
      (set! spans (cons (math-source-span start position p role) spans))))
  (define (sign p role s) (marked p role (lambda () (emit s))))
  (define (child v p i minprec)
    (define cp (append p (list i)))
    (if (or (< (precedence v) minprec)
            (and (number? v) (negative? v) (>= minprec 3))
            (and (>= minprec 4)
                 (or (memq (head v) '(/ expt sqrt))
                     (and (number? v) (exact? v) (rational? v) (not (integer? v))))))
      (let ([tall? (or (eq? (head v) '/)
                       (and (number? v) (exact? v) (rational? v) (not (integer? v))))])
        (sign cp 'left-parenthesis (if tall? "\\Bigl(" "("))
        (walk v cp)
        (sign cp 'right-parenthesis (if tall? "\\Bigr)" ")")))
      (walk v cp)))
  (define (walk x p)
    (marked p 'expression
      (lambda ()
        (match x
          [#t (sign p 'truth "\\text{all real values}")]
          [#f (sign p 'truth "\\text{no real solutions}")]
          [(? number?)
           ;; Sign and magnitude share one mathematical occurrence, but the sign
           ;; has its own role in every context (not only after a plus operator).
           ;; Reordering a negative number can therefore carry its sign intact.
           (when (or (negative? x) (eqv? x -0.0)) (sign p 'sign "-"))
           (define magnitude (abs x))
           (sign p 'atom
             (if (and (exact? magnitude) (rational? magnitude) (not (integer? magnitude)))
                 (format "\\frac{~a}{~a}" (numerator magnitude) (denominator magnitude))
                 (number->string magnitude)))]
          [(? symbol?) (sign p 'atom (variable-tex x))]
          [(list '+ vs ...)
           (for ([v (in-list vs)] [i (in-naturals)])
             (cond
               [(zero? i) (child v p i 2)]
               [(and (number? v) (negative? v))
                ;; The sign is part of this negative number's occurrence.
                (sign (append p (list i)) 'sign "-")
                (marked
                  (append p (list i))
                  'atom
                  (lambda ()
                    (emit
                      (if (and (exact? v) (rational? v) (not (integer? v)))
                        (format "\\frac{~a}{~a}" (abs (numerator v)) (denominator v))
                        (number->string (- v))))))]
               [(match v [(list '- _) #t] [_ #f])
                (sign (append p (list i)) 'operator "-")
                (child (cadr v) (append p (list i)) 0 3)]
               [(and (eq? (head v) '*) (number? (cadr v)) (negative? (cadr v)))
                (child v p i 2)]
               [else (sign p (string->symbol (format "operator-~a" i)) "+") (child v p i 2)]))]
          [(list '- u) (sign p 'operator "-") (child u p 0 3)]
          [(list '- u v) (child u p 0 2) (sign p 'operator "-") (child v p 1 3)]
          [(list '* vs ...)
           (for ([v (in-list vs)] [i (in-naturals)])
             (when (positive? i)
               (define prev (list-ref vs (sub1 i)))
               (when (or
                       (eq? multiplication 'explicit)
                       (equal? prev 1)
                       (and (number? v) (number? prev))
                       (and (number? v) (negative? v)))
                 (sign p (string->symbol (format "operator-~a" i)) "\\cdot ")))
             (if (and (zero? i) (number? v)) (walk v (append p (list i))) (child v p i 3)))]
          [(list '/ u v)
           (emit "\\frac{")
           (walk u (append p '(0)))
           (emit "}{")
           (walk v (append p '(1)))
           (emit "}")]
          [(list 'expt u v)
           ;; An explicitly tall/compound base is one TeX nucleus. Ordinary
           ;; italic symbols are left ungrouped so their script correction stays intact.
           (define grouped? (or (memq (head u) '(/ sqrt expt))
                                (and (number? u) (exact? u) (rational? u) (not (integer? u)))))
           (when grouped? (emit "{"))
           (child u p 0 4)
           (when grouped? (emit "}"))
           (emit "^{") (walk v (append p '(1))) (emit "}")]
          [(list 'sqrt u) (emit "\\sqrt{") (walk u (append p '(0))) (emit "}")]
          [(list 'abs u)
           (sign p 'left-delimiter "\\lvert ")
           (walk u (append p '(0)))
           (sign p 'right-delimiter "\\rvert ")]
          [(list 'parens u)
           (sign p 'left-parenthesis "(")
           (walk u (append p '(0)))
           (sign p 'right-parenthesis ")")]
          [(list (and op (or '= '< '<= '> '>=)) u v)
           (walk u (append p '(0)))
           (sign p 'relation
             (case op [(=) "="] [(<) "<"] [(>) ">"] [(<=) "\\leq "] [(>=) "\\geq "]))
           (walk v (append p '(1)))]
          [(list 'not (list '= u v))
           (walk u (append p '(0 0)))
           (sign p 'relation "\\ne ")
           (walk v (append p '(0 1)))]
          [(list 'not u) (sign p 'operator "\\neg ") (child u p 0 1)]
          [(list (and op (or 'and 'or)) vs ...)
           (for ([v (in-list vs)] [i (in-naturals)])
             (when (positive? i)
               (sign p
                 (string->symbol (format "operator-~a" i))
                 (if (eq? op 'or) "\\text{ or }" "\\text{ and }")))
             (child v p i 1))]
          [(list f vs ...)
           (sign p 'function
             (if (memq f '(sin cos tan ln log exp))
               (format "\\~a" f)
               (format "\\operatorname{~a}" (escape (symbol->string f)))))
           (sign p 'left-parenthesis "(")
           (for ([v (in-list vs)] [i (in-naturals)])
             (when (positive? i) (sign p (string->symbol (format "comma-~a" i)) ","))
             (walk v (append p (list i))))
           (sign p 'right-parenthesis ")")]))))
  (walk d '())
  (math-source
    (get-output-string output)
    (sort (reverse spans) < #:key math-source-span-start)))

;;;
;;; Public Notation Conversions
;;;
; datum->tex : math-datum? [#:multiplication symbol?] -> string?
;;   Returns complete TeX source without evaluating or normalizing the expression.
(define (datum->tex d #:multiplication [m 'school])
  (math-source-text (format-math-source d #:multiplication m)))

; math->tex : (or/c math? math-datum?) [#:multiplication symbol?] -> string?
;;   Returns complete TeX source without evaluating or normalizing the expression.
(define math->tex
  datum->tex)

; math->string : (or/c math? math-datum?) -> string?
;;   Prints the held S-expression for inspection.
(define (math->string x)
  (format "~s" (if (math? x) (math-datum x) x)))
