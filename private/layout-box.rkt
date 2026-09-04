#lang racket/base

;;;
;;; Renderer Layout Boxes
;;;

;; The geometry-only box vocabulary is shared by ordinary relative layout and
;; renderer-aware relation contexts.  Keeping it out of pict-adapter prevents a
;; dependency cycle when a layout relation asks for aggregate selection bounds.

(require "geometry.rkt")

(provide (struct-out layout-box)
         layout-horizontal-alignment?
         layout-vertical-alignment?
         layout-box-anchor?
         layout-box-width
         layout-box-height
         layout-box-center
         layout-box-anchor)

(struct layout-box (left bottom right top)
  #:transparent
  #:guard
  (lambda (left bottom right top who)
    (unless (finite-real? left)
      (raise-argument-error who "finite real?" left))
    (unless (finite-real? bottom)
      (raise-argument-error who "finite real?" bottom))
    (unless (finite-real? right)
      (raise-argument-error who "finite real?" right))
    (unless (finite-real? top)
      (raise-argument-error who "finite real?" top))
    (when (> left right)
      (raise-arguments-error
       who "a layout box left edge must not exceed its right edge"
       "left" left "right" right))
    (when (> bottom top)
      (raise-arguments-error
       who "a layout box bottom edge must not exceed its top edge"
       "bottom" bottom "top" top))
    (values left bottom right top)))

(define (layout-horizontal-alignment? value)
  (and (symbol? value) (memq value '(left center right)) #t))

(define (layout-vertical-alignment? value)
  (and (symbol? value) (memq value '(bottom center top)) #t))

(define (layout-box-anchor? value)
  (and (symbol? value)
       (memq value
             '(bottom-left bottom bottom-right
               left center right
               top-left top top-right))
       #t))

(define (layout-box-width box)
  (check-layout-box 'layout-box-width box)
  (- (layout-box-right box) (layout-box-left box)))

(define (layout-box-height box)
  (check-layout-box 'layout-box-height box)
  (- (layout-box-top box) (layout-box-bottom box)))

(define (layout-box-center box)
  (check-layout-box 'layout-box-center box)
  (vec2 (/ (+ (layout-box-left box) (layout-box-right box)) 2)
        (/ (+ (layout-box-bottom box) (layout-box-top box)) 2)))

(define (layout-box-anchor box anchor)
  (check-layout-box 'layout-box-anchor box)
  (unless (layout-box-anchor? anchor)
    (raise-argument-error 'layout-box-anchor "layout-box-anchor?" anchor))
  (case anchor
    [(bottom-left) (vec2 (layout-box-left box) (layout-box-bottom box))]
    [(bottom) (vec2 (vec2-x (layout-box-center box)) (layout-box-bottom box))]
    [(bottom-right) (vec2 (layout-box-right box) (layout-box-bottom box))]
    [(left) (vec2 (layout-box-left box) (vec2-y (layout-box-center box)))]
    [(center) (layout-box-center box)]
    [(right) (vec2 (layout-box-right box) (vec2-y (layout-box-center box)))]
    [(top-left) (vec2 (layout-box-left box) (layout-box-top box))]
    [(top) (vec2 (vec2-x (layout-box-center box)) (layout-box-top box))]
    [(top-right) (vec2 (layout-box-right box) (layout-box-top box))]))

(define (check-layout-box who value)
  (unless (layout-box? value)
    (raise-argument-error who "layout-box?" value)))
