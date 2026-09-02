#lang racket/base

;; Construction coverage for the source-preserving algebra example.

(require rackunit
         "../main.rkt"
         "../examples/copying-and-emphasizing-formula-parts.rkt")

(define (formula-at scene time)
  (scene-visual-at scene 'equation time))

(define (formula-sources scene time)
  (map (lambda (part)
         (formula-visual-source (formula-part-formula part)))
       (formula-assembly-visual-parts (formula-at scene time))))

(define (equals-position scene time)
  (visual-position
   (formula-part-formula
    (for/first ([part (in-list (formula-assembly-visual-parts
                                (formula-at scene time)))]
                #:when (string=? (formula-visual-source
                                  (formula-part-formula part))
                                 "="))
      part))))

(define (part-position scene time name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref (formula-at scene time) name))))

(define (source-position scene time source)
  (visual-position
   (formula-part-formula
    (for/first ([part (in-list (formula-assembly-visual-parts
                                (formula-at scene time)))]
                #:when (string=? (formula-visual-source
                                  (formula-part-formula part))
                                 source))
      part))))

(module+ test
  (define demo (make-demo-scene))
  (check-equal? (formula-sources demo 0) '("x" "=" "2"))
  (check-equal? (formula-sources demo 7) '("x" "+" "x" "=" "2" "+" "x"))
  (check-equal? (equals-position demo 0) (equals-position demo 7))
  ;; Existing terms retain their exact coordinates while copies form the new
  ;; outside terms. In particular, 2 must not slide horizontally as the target
  ;; formula is installed at the end of the clip. (TeX owns the y offsets
  ;; necessary to put different glyphs on a common mathematical baseline.)
  (check-equal? (vec2-x (source-position demo 5 "2"))
                (vec2-x (source-position demo 6 "2")))
  (check-equal? (vec2-x (source-position demo 5 "2"))
                (vec2-x (source-position demo 7 "2")))
  (check-equal? (vec2-x (part-position demo 5 'original-x))
                (vec2-x (part-position demo 7 'added-x-left)))
  ;; Tagged fragments from different whole formulas have different cropped SVG
  ;; resources. Unchanged terms keep their source resource at the endpoint so
  ;; the final frame cannot swap glyph crops.
  (check-equal?
   (tagged-formula-fragment-visual-svg-source
    (formula-part-formula
     (formula-assembly-visual-ref (formula-at demo 0) 'two)))
   (tagged-formula-fragment-visual-svg-source
    (formula-part-formula
     (formula-assembly-visual-ref (formula-at demo 7) 'two))))
  (check-equal?
   (tagged-formula-fragment-visual-svg-source
    (formula-part-formula
     (formula-assembly-visual-ref (formula-at demo 0) 'original-x)))
   (tagged-formula-fragment-visual-svg-source
    (formula-part-formula
     (formula-assembly-visual-ref (formula-at demo 7) 'added-x-right))))
  ;; The operation midpoint contains the ordinary transformed source x and
  ;; two independently travelling copies.
  (check-equal?
   (length (filter (lambda (source) (string=? source "x"))
                   (formula-sources demo 6)))
   3)
  ;; Temporary attention overlays disappear at their clip boundaries.
  (check-equal? (scene-state-count (scene-sample demo 13/4)) 6)
  (check-equal? (scene-state-count (scene-sample demo 9/2)) 6))
