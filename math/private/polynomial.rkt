#lang racket/base

;;;
;;; Exact Polynomial Checks
;;;
;; Implements bounded exact polynomial and rational-identity checks for elementary
;; real-scalar rewrites; it is not a general CAS.

;;;
;;; Imports and Exports
;;;
;; Imports
(require racket/list (only-in racket/match match) "datum.rkt")

;; Exports
(provide
  rational-equivalent? polynomial-zero? polynomial-constant polynomial-key
  polynomial-normal-form polynomial-in? (struct-out rational-polynomial)
  datum->rational-polynomial)

;;;
;;; Data Representation
;;;
(struct rational-polynomial (numerator denominator)
  #:transparent)
;; rational-polynomial is an immutable record. Its fields have the following roles.
;;  - numerator  immutable-hash?  sparse exact numerator coefficients
;;  - denominator  immutable-hash?  nonzero sparse exact denominator coefficients

; zero : immutable-hash?
;;   Represents the exact zero sparse polynomial.
(define zero
  (hash))

; one : immutable-hash?
;;   Represents the exact unit sparse polynomial.
(define one
  (hash '() 1))

; constant : any/c -> immutable-hash?
;;   Builds a sparse exact polynomial constant or formal atom.
(define (constant n)
  (if (zero? n) zero (hash '() n)))

; atom : any/c -> immutable-hash?
;;   Builds a sparse exact polynomial constant or formal atom.
(define (atom x)
  (hash (list (cons x 1)) 1))

; key<? : any/c any/c -> boolean?
;;   Orders polynomial keys deterministically for canonical output.
(define (key<? a b)
  (string<? (format "~s" a) (format "~s" b)))

; monomial* : any/c any/c -> list?
;;   Combines exact monomial exponents and restores deterministic key order.
(define (monomial* a b)
  (define h
    (for/fold ([h (make-immutable-hash a)]) ([entry (in-list b)])
      (hash-set h (car entry) (+ (cdr entry) (hash-ref h (car entry) 0)))))
  (sort (hash->list h) key<? #:key car))

; p+ : any/c any/c -> immutable-hash?
;;   Computes exact sparse polynomial arithmetic within the expansion budget.
(define (p+ a b)
  (for/fold ([r a]) ([(k c) (in-hash b)])
    (define v (+ c (hash-ref r k 0)))
    (if (zero? v) (hash-remove r k) (hash-set r k v))))

; pneg : any/c -> immutable-hash?
;;   Computes exact sparse polynomial arithmetic within the expansion budget.
(define (pneg a)
  (for/hash ([(k c) (in-hash a)]) (values k (- c))))

; p* : any/c any/c -> immutable-hash?
;;   Computes exact sparse polynomial arithmetic within the expansion budget.
(define (p* a b)
  (when (> (* (hash-count a) (hash-count b)) 20000)
    (error 'polynomial-check "polynomial expansion budget exceeded"))
  (for*/fold ([r zero]) ([(ka ca) (in-hash a)] [(kb cb) (in-hash b)])
    (p+ r (hash (monomial* ka kb) (* ca cb)))))

; p^ : any/c any/c -> immutable-hash?
;;   Computes exact sparse polynomial arithmetic within the expansion budget.
(define (p^ a n)
  (cond
    [(zero? n) one]
    [(even? n) (define h (p^ a (quotient n 2))) (p* h h)]
    [else (p* a (p^ a (sub1 n)))]))

; r+ : any/c any/c -> rational-polynomial?
;;   Computes exact rational-polynomial arithmetic without losing denominator
;;   information.
(define (r+ a b)
  (rational-polynomial
    (p+
      (p* (rational-polynomial-numerator a) (rational-polynomial-denominator b))
      (p* (rational-polynomial-numerator b) (rational-polynomial-denominator a)))
    (p* (rational-polynomial-denominator a) (rational-polynomial-denominator b))))

; rneg : any/c -> rational-polynomial?
;;   Computes exact rational-polynomial arithmetic without losing denominator
;;   information.
(define (rneg a)
  (rational-polynomial
    (pneg (rational-polynomial-numerator a))
    (rational-polynomial-denominator a)))

; r* : any/c any/c -> rational-polynomial?
;;   Computes exact rational-polynomial arithmetic without losing denominator
;;   information.
(define (r* a b)
  (rational-polynomial
    (p* (rational-polynomial-numerator a) (rational-polynomial-numerator b))
    (p* (rational-polynomial-denominator a) (rational-polynomial-denominator b))))

; rinv : any/c -> rational-polynomial?
;;   Computes exact rational-polynomial arithmetic without losing denominator
;;   information.
(define (rinv a)
  (when (zero? (hash-count (rational-polynomial-numerator a)))
    (error 'polynomial-check "identically zero denominator"))
  (rational-polynomial
    (rational-polynomial-denominator a)
    (rational-polynomial-numerator a)))

; rzero : rational-polynomial?
;;   Represents exact rational-polynomial zero.
(define rzero
  (rational-polynomial zero one))

; rone : rational-polynomial?
;;   Represents exact rational-polynomial one.
(define rone
  (rational-polynomial one one))

; datum->rational-polynomial : any/c -> rational-polynomial?
;;   Converts supported exact syntax to bounded rational-polynomial form.
(define (datum->rational-polynomial x)
  (define f datum->rational-polynomial)
  (match x
    [(? exact-rational? n) (rational-polynomial (constant n) one)]
    [(? number?) (error 'polynomial-check "exact coefficients required")]
    [(? boolean?) (error 'polynomial-check "a Boolean is not a scalar polynomial")]
    [(list '+ vs ...) (foldl r+ rzero (map f vs))]
    [(list '* vs ...) (foldl r* rone (map f vs))]
    [(list '- u) (rneg (f u))]
    [(list '- u v) (r+ (f u) (rneg (f v)))]
    [(list '/ u v) (r* (f u) (rinv (f v)))]
    [(list 'parens u) (f u)]
    [(list 'expt u (? exact-integer? n))
     (unless (<= (abs n) 64) (error 'polynomial-check "exponent budget exceeded"))
     (define b (if (negative? n) (rinv (f u)) (f u)))
     (rational-polynomial
       (p^ (rational-polynomial-numerator b) (abs n))
       (p^ (rational-polynomial-denominator b) (abs n)))]
    [_ (rational-polynomial (atom x) one)]))

; exact-rational? : any/c -> boolean?
;;   Recognizes exact rational coefficients.
(define (exact-rational? n)
  (and (rational? n) (exact? n)))

; rational-equivalent? : any/c any/c -> boolean?
;;   Checks a rational identity by exact cross multiplication, not sampled numbers.
(define (rational-equivalent? a b)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define aa (datum->rational-polynomial a))
    (define bb (datum->rational-polynomial b))
    (equal?
      (p* (rational-polynomial-numerator aa) (rational-polynomial-denominator bb))
      (p* (rational-polynomial-numerator bb) (rational-polynomial-denominator aa)))))

; polynomial-zero? : any/c -> boolean?
;;   Establishes an exact zero identity within the supported rational fragment.
(define (polynomial-zero? x)
  (rational-equivalent? x 0))

; polynomial-constant : any/c -> (or/c exact-rational? #f)
;;   Returns an exact constant when the supported polynomial reduces to one.
(define (polynomial-constant x)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define r (datum->rational-polynomial x))
    (define n (rational-polynomial-numerator r))
    (define d (rational-polynomial-denominator r))
    (cond
      [(zero? (hash-count n)) 0]
      [(and (= (hash-count d) 1) (hash-has-key? d '()) (= (hash-count n) 1) (hash-has-key? n '()))
       (/ (hash-ref n '()) (hash-ref d '()))]
      [else #f])))

; polynomial-key : any/c -> list?
;;   Returns deterministic sparse numerator and denominator keys.
(define (polynomial-key x)
  (define r (datum->rational-polynomial x))
  (list
    (sort (hash->list (rational-polynomial-numerator r)) key<? #:key car)
    (sort (hash->list (rational-polynomial-denominator r)) key<? #:key car)))

; polynomial-in? : any/c any/c -> boolean?
;;   Checks whether supported syntax is polynomial in the specified expression.
(define (polynomial-in? x v)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (define r (datum->rational-polynomial x))
    (for/and ([(m c) (in-hash (rational-polynomial-denominator r))])
      (for/and ([entry (in-list m)]) (free-of? (car entry) v)))))

; poly->datum : any/c -> math-datum?
;;   Writes sparse polynomial terms in deterministic canonical order.
(define (poly->datum p)
  (build-sum
    (for/list ([entry (in-list (sort (hash->list p) key<? #:key car))])
      (define m (car entry))
      (define c (cdr entry))
      (define powers
        (for/list ([e (in-list m)]) (if (= (cdr e) 1) (car e) `(expt ,(car e) ,(cdr e)))))
      (build-product (if (or (not (= c 1)) (null? powers)) (cons c powers) powers)))))

; polynomial-normal-form : any/c -> math-datum?
;;   Returns a calculation-only rational normal form without rewriting displayed states.
(define (polynomial-normal-form x)
  (define r (datum->rational-polynomial x))
  (define n (poly->datum (rational-polynomial-numerator r)))
  (define d (poly->datum (rational-polynomial-denominator r)))
  (if (equal? d 1) n `(/ ,n ,d)))
