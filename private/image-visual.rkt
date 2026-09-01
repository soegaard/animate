#lang racket/base

;;;
;;; Image Visual Model
;;;

;; Defines immutable bitmap-image references. The model stores a copied source
;; pathname and explicit world dimensions only; loading and raster caching stay
;; at the renderer boundary.

(require "affine-transform.rkt"
         "geometry.rkt"
         "visual-model.rkt")

(provide image
         image-visual?
         image-visual-source
         image-visual-width
         image-visual-height)

(struct image-visual (id transform opacity source width height)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (image-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation (image-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy image-visual visual
                  [transform
                   (affine-transform-with-translation
                    (image-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (image-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy image-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (image-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy image-visual visual [opacity opacity]))])

;; image-visual represents one placed bitmap source.
;;  - id         symbol?                  stable Visual identity.
;;  - transform  affine-transform?        placement and deformation.
;;  - opacity    opacity?                 global image opacity.
;;  - source     immutable-string?        renderer-resolved image pathname.
;;  - width      positive finite real?    unscaled local world width.
;;  - height     positive finite real?    unscaled local world height.
;;
;; The source is intentionally not opened here. This keeps scene construction,
;; sampling, and timeline compilation independent of filesystem state.

; image : path-string? #:id symbol?
;         [#:center vec2?]
;         [#:rotation finite-real?]
;         [#:scale scale-factor?]
;         [#:opacity opacity?]
;         #:width positive-finite-real?
;         #:height positive-finite-real?
;         -> image-visual?
;; Creates a semantic bitmap-image reference with explicit world dimensions.
(define (image source
               #:id id
               #:center [center origin]
               #:rotation [rotation 0]
               #:scale [scale 1]
               #:opacity [opacity 1]
               #:width width
               #:height height)
  (unless (symbol? id)
    (raise-argument-error 'image "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'image "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'image "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'image
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error 'image "finite real in [0, 1]" opacity))
  (check-image-length 'image "width" width)
  (check-image-length 'image "height" height)
  (image-visual id
                (make-affine-transform #:translation center
                                       #:rotation rotation
                                       #:scale scale)
                opacity
                (copy-image-source 'image source)
                width
                height))

; copy-image-source : symbol? any/c -> immutable-string?
(define (copy-image-source who source)
  (unless (path-string? source)
    (raise-argument-error who "path-string?" source))
  (define source-string
    (cond [(path? source) (path->string source)]
          [(string? source) source]
          [else
           (raise-argument-error who "path-string?" source)]))
  (string->immutable-string source-string))

; check-image-length : symbol? string? any/c -> void?
(define (check-image-length who field-name value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-arguments-error who
                           "an image dimension must be a positive finite real"
                           field-name value)))
