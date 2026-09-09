#lang racket/base

;;;
;;; Oklab Conversion and Gamut Policy
;;;

;; This pure module works on normalized linear-light RGB triples.  It is
;; deliberately independent of rgba-color, themes, rendering, and 3D so the
;; color-expression resolver and all later preparation paths use one model.

(require "geometry.rkt")

(provide linear-rgb->oklab
         oklab->linear-rgb
         oklab->gamut-mapped-linear-rgb)


;; linear-rgb->oklab : (list/c unit-real? unit-real? unit-real?) -> (list/c real? real? real?)
;; Converts a display-gamut linear RGB triple using Björn Ottosson's Oklab
;; matrices (2021 revision).
(define (linear-rgb->oklab rgb)
  (check-linear-rgb 'linear-rgb->oklab rgb)
  (define red (car rgb))
  (define green (cadr rgb))
  (define blue (caddr rgb))
  (define l (cube-root (+ (* 0.4122214708 red) (* 0.5363325363 green) (* 0.0514459929 blue))))
  (define m (cube-root (+ (* 0.2119034982 red) (* 0.6806995451 green) (* 0.1073969566 blue))))
  (define s (cube-root (+ (* 0.0883024619 red) (* 0.2817188376 green) (* 0.6299787005 blue))))
  (list (+ (* 0.2104542553 l) (* 0.7936177850 m) (* -0.0040720468 s))
        (+ (* 1.9779984951 l) (* -2.4285922050 m) (* 0.4505937099 s))
        (+ (* 0.0259040371 l) (* 0.7827717662 m) (* -0.8086757660 s))))

;; oklab->linear-rgb : (list/c finite-real? finite-real? finite-real?) -> (listof finite-real?)
;; Converts an Oklab triple to linear RGB without a gamut adjustment.
(define (oklab->linear-rgb lab)
  (check-oklab 'oklab->linear-rgb lab)
  (define lightness (car lab))
  (define a (cadr lab))
  (define b (caddr lab))
  (define l (cube (+ lightness (* 0.3963377774 a) (* 0.2158037573 b))))
  (define m (cube (+ lightness (* -0.1055613458 a) (* -0.0638541728 b))))
  (define s (cube (+ lightness (* -0.0894841775 a) (* -1.2914855480 b))))
  (list (+ (* 4.0767416621 l) (* -3.3077115913 m) (* 0.2309699292 s))
        (+ (* -1.2684380046 l) (* 2.6097574011 m) (* -0.3413193965 s))
        (+ (* -0.0041960863 l) (* -0.7034186147 m) (* 1.7076147010 s))))

;; oklab->gamut-mapped-linear-rgb : ... -> (list/c unit-real? unit-real? unit-real?)
;; Uses fixed-lightness, fixed-hue chroma reduction when an Oklab result lies
;; outside sRGB.  Twenty-four binary-search steps make this policy deterministic
;; and avoid undocumented per-channel clipping.
(define (oklab->gamut-mapped-linear-rgb lab)
  (check-oklab 'oklab->gamut-mapped-linear-rgb lab)
  (define direct (oklab->linear-rgb lab))
  (cond [(unit-rgb? direct) direct]
        [else
         (define lightness (car lab))
         (define a (cadr lab))
         (define b (caddr lab))
         (define-values (chroma-scale ignored-high)
           (for/fold ([low 0.0] [high 1.0]) ([unused (in-range 24)])
             (define middle (/ (+ low high) 2.0))
             (if (unit-rgb? (oklab->linear-rgb (list lightness (* middle a) (* middle b))))
                 (values middle high)
                 (values low middle))))
         (define mapped
           (oklab->linear-rgb (list lightness (* chroma-scale a) (* chroma-scale b))))
         (map clamp-unit mapped)]))

(define (cube-root value) (expt value (/ 1.0 3.0)))
(define (cube value) (* value value value))

(define (unit-rgb? rgb)
  (and (= (length rgb) 3)
       (for/and ([channel (in-list rgb)])
         (and (finite-real? channel) (<= 0 channel 1)))))

(define (check-linear-rgb who rgb)
  (unless (and (list? rgb) (unit-rgb? rgb))
    (raise-argument-error who "a list of three finite real channels in [0, 1]" rgb)))

(define (check-oklab who lab)
  (unless (and (list? lab) (= (length lab) 3)
               (andmap finite-real? lab))
    (raise-argument-error who "a list of three finite Oklab channels" lab)))

(define (clamp-unit value) (min 1 (max 0 value)))
