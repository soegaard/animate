#lang racket/base

;;;
;;; Coefficient and SVG Contract Tests
;;;
;; Checks finite coefficient grids and semantic source ownership using exact
;; mathematical invariants.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append-map)
  (only-in racket/match match)
  "check.rkt"
  "../main.rkt"
  "../private/datum.rkt"
  "../private/semantic-svg.rkt"
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;; Exports
(provide run-property-tests)

;;;
;;; Construction and Operations
;;;
; value : any/c any/c -> any/c
;;   Evaluates a test expression under an explicit finite coefficient assignment.
(define (value x env)
  (match x
    [(? number?) x]
    [(? boolean?) x]
    [(? symbol?) (hash-ref env x)]
    [(list '+ xs ...) (apply + (map (lambda (x) (value x env)) xs))]
    [(list '- xs ...) (apply - (map (lambda (x) (value x env)) xs))]
    [(list '* xs ...) (apply * (map (lambda (x) (value x env)) xs))]
    [(list '/ a b) (/ (value a env) (value b env))]
    [(list 'expt a b) (expt (value a env) (value b env))]
    [(list 'sqrt a) (sqrt (value a env))]
    [(list '= a b) (= (value a env) (value b env))]
    [(list '> a b) (> (value a env) (value b env))]
    [(list '< a b) (< (value a env) (value b env))]
    [(list '>= a b) (>= (value a env) (value b env))]
    [(list '<= a b) (<= (value a env) (value b env))]
    [(list 'not a) (not (value a env))]
    [(list 'and xs ...) (andmap (lambda (x) (value x env)) xs)]
    [(list 'or xs ...) (ormap (lambda (x) (value x env)) xs)]))

; selected-segments : presentation-plan? any/c -> list?
;;   Selects the lesson branches whose guards hold for a coefficient assignment.
(define (selected-segments plan env)
  (filter
    (lambda (segment)
      (define ctx (plan-segment-context segment))
      (and (not (plan-segment-shared? segment))
      (for/and ([p (in-list (math-context-assumptions ctx))])
        (value (definition-expand p (math-context-definitions ctx)) env))))
    (presentation-plan-segments plan)))

; solution-values : math-datum? any/c -> list?
;;   Extracts and evaluates the roots asserted by a completed test derivation.
(define (solution-values d env)
  (match d
    [(list '= 'x rhs) (list (value rhs env))]
    [(list 'or ds ...) (append-map (lambda (x) (solution-values x env)) ds)]
    [_ '()]))

; run-property-tests : -> void?
;;   Runs the named regression groups and records failures in the test harness.
(define (run-property-tests)
  (test-group
    "general linear equation: coefficient grid"
    (lambda ()
      (for* ([a (in-range -2 3)] [b (in-range -2 3)] [c (in-range -2 3)])
        (define env (hash 'a a 'b b 'c c))
        (define selected (selected-segments lg:plan env))
        (check-equal (length selected) 1 'unique-linear-case)
        (define d (math-datum (after (plan-segment-derivation (car selected)))))
        (cond
          [(zero? a) (check-equal d (= b c) 'degenerate-linear)]
          [else
           (define roots (solution-values d env))
           (check-equal roots (list (/ (- c b) a)) 'general-linear-root)]))))
  (test-group
    "general quadratic: positive, negative and zero coefficients"
    (lambda ()
      (for* ([a (in-range -2 3)] [b (in-range -3 4)] [c (in-range -2 3)])
        (define env (hash 'a a 'b b 'c c))
        (define selected (selected-segments qg:plan env))
        (check-equal (length selected) 1 'unique-quadratic-case)
        (define segment (car selected))
        (define d
          (definition-expand
            (math-datum (after (plan-segment-derivation segment)))
            (math-context-definitions (plan-segment-context segment))))
        (define disc (- (* b b) (* 4 a c)))
        (cond
          [(and (zero? a) (zero? b)) (check-equal d (zero? c) 'constant-polynomial)]
          [(zero? a)
           (check-equal (solution-values d env) (list (/ (- c) b)) 'degenerate-quadratic)]
          [(negative? disc) (check-equal d #f 'no-real-root)]
          [else
           (define roots (solution-values d env))
           (check-equal (length roots) (if (zero? disc) 1 2) 'root-multiplicity)
           (for ([x (in-list roots)])
             (check-close (+ (* a x x) (* b x) c) 0 1e-8 'original-polynomial-residual))]))))
  (test-group
    "semantic SVG ownership and source range contracts"
    (lambda ()
      (define svg
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 10'><defs><path id='font-glyph' d='M0 0L1 1'/></defs><g transform='translate(2,3)'><g id='animate-math-0'><path id='bar' d='M0 0L8 0'/><g id='animate-math-1'><use href='#font-glyph'/></g></g><g id='animate-math-2'><path id='sibling' d='M9 0L10 1'/></g></g></svg>")
      (check-equal
        (svg-marker-ids svg)
        '("animate-math-0" "animate-math-1" "animate-math-2"))
      (define parent (isolate-svg-marker svg "animate-math-0"))
      (define child (isolate-svg-marker svg "animate-math-1"))
      (check-true (regexp-match? #rx"bar" parent))
      (check-false (regexp-match? #rx"<use" parent))
      (check-false (regexp-match? #rx"sibling" parent))
      (check-true (regexp-match? #rx"translate\\(2,3\\)" child))
      (check-true (regexp-match? #rx"<use" child))
      (check-true (regexp-match? #rx"font-glyph" child))
      (check-false (regexp-match? #rx"id=\"bar\"" child))
      (check-equal (svg-view-box child) '(0 0 20 10))
      (check-true (regexp-match? #rx"#ABCDEF" (recolor-svg child "#ABCDEF")))
      (define glyphs-a
        "<svg xmlns='http://www.w3.org/2000/svg'><defs><path id='g2' d='M2 2'/><path id='g1' d='M1 1'/></defs><use href='#g1'/></svg>")
      (define glyphs-b
        "<svg xmlns='http://www.w3.org/2000/svg'><defs><path id='g1' d='M1 1'/><path id='g2' d='M2 2'/></defs><use href='#g1'/></svg>")
      (check-equal (canonicalize-svg-definitions glyphs-a)
                   (canonicalize-svg-definitions glyphs-b)
                   'glyph-definition-order-is-content-independent)
      (define glyphs-with-whitespace
        "<svg xmlns='http://www.w3.org/2000/svg'><defs>\n<path id='g2' d='M2 2'/>\n<path id='g1' d='M1 1'/>\n</defs><use href='#g1'/></svg>")
      (define canonical-glyphs-with-whitespace
        (canonicalize-svg-definitions glyphs-with-whitespace))
      (check-true
       (< (caar (regexp-match-positions #rx"id=\"g1\"" canonical-glyphs-with-whitespace))
          (caar (regexp-match-positions #rx"id=\"g2\"" canonical-glyphs-with-whitespace)))
       'glyph-definition-order-ignores-interstitial-whitespace)
      (for ([datum
             (in-list
               '((= (expt x 2) 4)
                  (= (/ (+ (* 3 x) 5) (expt a 2)) (sqrt (+ b 1)))
                  (= (* 3 x) (/ 12 3))
                  (= (expt (- (+ x 3)) 2) 4)))])
        (define src (format-math-source datum))
        (define-values (marked markers) (annotate-math-source src))
        (check-equal (length markers) (length (math-source-spans src)))
        (check-equal (length (regexp-match* #rx"dvisvgm:raw <g" marked)) (length markers))
        (check-equal (length (regexp-match* #rx"dvisvgm:raw </g>" marked)) (length markers))))))
