#lang racket/base

;;;
;;; Immutable Preview Quality Levels
;;;

(provide preview-quality
         preview-quality?
         preview-quality-name
         preview-quality-pixel-scale
         preview-quality-supersample
         thumbnail-preview-quality
         draft-preview-quality
         full-preview-quality
         preview-quality-satisfies?
         preview-quality-rank)

(struct preview-quality-value (name pixel-scale supersample)
  #:transparent
  #:constructor-name make-preview-quality)

(define preview-quality? preview-quality-value?)
(define preview-quality-name preview-quality-value-name)
(define preview-quality-pixel-scale preview-quality-value-pixel-scale)
(define preview-quality-supersample preview-quality-value-supersample)

(define (preview-quality #:name name #:pixel-scale pixel-scale #:supersample supersample)
  (unless (symbol? name)
    (raise-argument-error 'preview-quality "symbol?" name))
  (unless (and (real? pixel-scale) (positive? pixel-scale))
    (raise-argument-error 'preview-quality "positive real?" pixel-scale))
  (unless (exact-positive-integer? supersample)
    (raise-argument-error 'preview-quality "exact-positive-integer?" supersample))
  (make-preview-quality name pixel-scale supersample))

(define thumbnail-preview-quality
  (preview-quality #:name 'thumbnail #:pixel-scale 1/4 #:supersample 1))

(define draft-preview-quality
  (preview-quality #:name 'draft #:pixel-scale 1/2 #:supersample 1))

(define full-preview-quality
  (preview-quality #:name 'full #:pixel-scale 1 #:supersample 1))

; preview-quality-satisfies? : preview-quality? preview-quality? -> boolean?
;; A higher-quality cached bitmap can satisfy a lower-quality request by
;; downscaling. A lower-quality bitmap must never satisfy a full request.
(define (preview-quality-satisfies? available requested)
  (check-quality 'preview-quality-satisfies? available)
  (check-quality 'preview-quality-satisfies? requested)
  (and (>= (preview-quality-pixel-scale available)
           (preview-quality-pixel-scale requested))
       (>= (preview-quality-supersample available)
           (preview-quality-supersample requested))))

(define (preview-quality-rank quality)
  (check-quality 'preview-quality-rank quality)
  (* (preview-quality-pixel-scale quality)
     (preview-quality-supersample quality)))

(define (check-quality who value)
  (unless (preview-quality? value)
    (raise-argument-error who "preview-quality?" value)))
