#lang racket/base

;;;
;;; Rendered SVG Visual Model
;;;

;; Represents one SVG document as an opaque, full-fidelity rendered Visual.
;; This complements `svg->visual`: that constructor imports a deliberately
;; small semantic subset whose named parts can be animated independently,
;; whereas `svg-image` retains the source document for the svg package's
;; static renderer.

(require "affine-transform.rkt"
         "geometry.rkt"
         "visual-model.rkt")

(provide svg-image
         svg-image-visual?
         svg-image-visual-source
         svg-image-visual-width
         svg-image-visual-height)

(struct svg-image-visual (id transform opacity source width height)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (svg-image-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation (svg-image-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy svg-image-visual visual
                  [transform
                   (affine-transform-with-translation
                    (svg-image-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (svg-image-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy svg-image-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (svg-image-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy svg-image-visual visual [opacity opacity]))])

; svg-image : path-string? #:id symbol?
;             [#:center vec2?] [#:rotation finite-real?]
;             [#:scale scale-factor?] [#:opacity opacity?]
;             #:width positive-finite-real? #:height positive-finite-real?
;             -> svg-image-visual?
;; Creates an opaque, full-fidelity SVG source reference with explicit world
;; dimensions. The source remains unopened until the Pict renderer needs it.
(define (svg-image source
                   #:id id
                   #:center [center origin]
                   #:rotation [rotation 0]
                   #:scale [scale 1]
                   #:opacity [opacity 1]
                   #:width width
                   #:height height)
  (unless (symbol? id)
    (raise-argument-error 'svg-image "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'svg-image "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'svg-image "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'svg-image
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error 'svg-image "finite real in [0, 1]" opacity))
  (check-svg-image-length 'svg-image "width" width)
  (check-svg-image-length 'svg-image "height" height)
  (svg-image-visual id
                    (make-affine-transform #:translation center
                                           #:rotation rotation
                                           #:scale scale)
                    opacity
                    (copy-svg-image-source 'svg-image source)
                    width
                    height))

; copy-svg-image-source : symbol? any/c -> immutable-string?
(define (copy-svg-image-source who source)
  (unless (path-string? source)
    (raise-argument-error who "path-string?" source))
  (define source-string
    (cond [(path? source) (path->string source)]
          [(string? source) source]
          [else
           (raise-argument-error who "path-string?" source)]))
  (string->immutable-string source-string))

; check-svg-image-length : symbol? string? any/c -> void?
(define (check-svg-image-length who field-name value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-arguments-error who
                           "an SVG image dimension must be a positive finite real"
                           field-name value)))
