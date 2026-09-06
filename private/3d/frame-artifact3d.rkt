#lang racket/base

;;;
;;; Immutable Renderer Frame Artifacts
;;;

;; One frame artifact is the common result consumed by viewport composition,
;; label occlusion, picking diagnostics, and future annotation layout. It never
;; owns native resources; backends may omit attachments they cannot provide.

(require racket/list
         "camera3d.rkt"
         "vec3.rkt")

(provide renderer3d-attachment-symbols
         renderer3d-canonical-attachments
         renderer3d-attachment-set-satisfies?
         (struct-out renderer3d-frame-artifact)
         renderer3d-frame-artifact-attachments
         renderer3d-frame-linear-depth-at
         renderer3d-frame-object-at
         renderer3d-frame-project)

;; Attachment names are protocol values, not backend-private implementation
;; details. A renderer may return a strict superset, but it must never pretend
;; that an absent requested attachment is available.
(define renderer3d-attachment-symbols '(color linear-depth object-id normal))

; renderer3d-canonical-attachments : (listof symbol?) -> immutable-listof symbol?
;; Validates names, removes duplicates, and gives every renderer/cache one
;; deterministic attachment order.
(define (renderer3d-canonical-attachments attachments)
  (unless (list? attachments)
    (raise-argument-error 'renderer3d-canonical-attachments "list?" attachments))
  (for ([attachment (in-list attachments)])
    (unless (memq attachment renderer3d-attachment-symbols)
      (raise-arguments-error
       'renderer3d-canonical-attachments
       "a list of known 3D renderer attachments"
       "attachment" attachment
       "known-attachments" renderer3d-attachment-symbols)))
  (when (null? attachments)
    (raise-argument-error 'renderer3d-canonical-attachments "nonempty attachment list" attachments))
  (sort (remove-duplicates attachments) symbol<?))

(define (renderer3d-attachment-set-satisfies? available required)
  (andmap (lambda (attachment) (memq attachment available)) required))

(struct renderer3d-frame-artifact
  (width height straight-argb linear-depth-snapshot object-id-snapshot normal-snapshot camera diagnostics)
  #:transparent
  #:guard
  (lambda (width height straight-argb linear-depth-snapshot object-id-snapshot normal-snapshot
                 camera diagnostics who)
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer? width" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer? height" height))
    (define pixel-count (* width height))
    (unless (or (not straight-argb)
                (and (bytes? straight-argb) (= (bytes-length straight-argb) (* 4 pixel-count))))
      (raise-argument-error who "(or/c #f ARGB bytes matching width and height)" straight-argb))
    (for ([snapshot (in-list (list linear-depth-snapshot object-id-snapshot normal-snapshot))]
          [name (in-list '(linear-depth object-id normal))])
      (unless (or (not snapshot)
                  (and (vector? snapshot) (= (vector-length snapshot) pixel-count)))
        (raise-arguments-error who "an optional pixel snapshot matching width and height"
                               "attachment" name "snapshot" snapshot)))
    (unless (camera3d? camera)
      (raise-argument-error who "camera3d?" camera))
    (values width height
            (and straight-argb (bytes->immutable-bytes straight-argb))
            (freeze-snapshot linear-depth-snapshot)
            (freeze-snapshot object-id-snapshot)
            (freeze-snapshot normal-snapshot)
            camera diagnostics)))

(define (freeze-snapshot snapshot)
  (and snapshot (vector->immutable-vector snapshot)))

(define (renderer3d-frame-artifact-attachments artifact)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-artifact "renderer3d-frame-artifact?" artifact))
  (renderer3d-canonical-attachments
   (append (if (renderer3d-frame-artifact-straight-argb artifact) '(color) '())
           (if (renderer3d-frame-artifact-linear-depth-snapshot artifact) '(linear-depth) '())
           (if (renderer3d-frame-artifact-object-id-snapshot artifact) '(object-id) '())
           (if (renderer3d-frame-artifact-normal-snapshot artifact) '(normal) '()))))

; renderer3d-frame-linear-depth-at : renderer3d-frame-artifact? integer? integer? -> (or/c #f real?)
;; Returns one top-down view depth only when the backend requested/provided it.
(define (renderer3d-frame-linear-depth-at artifact x y)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-linear-depth-at "renderer3d-frame-artifact?" artifact))
  (unless (and (exact-nonnegative-integer? x) (< x (renderer3d-frame-artifact-width artifact))
               (exact-nonnegative-integer? y) (< y (renderer3d-frame-artifact-height artifact)))
    (raise-argument-error 'renderer3d-frame-linear-depth-at "in-bounds pixel coordinates" (vector x y)))
  (define values (renderer3d-frame-artifact-linear-depth-snapshot artifact))
  (and values (vector-ref values (+ x (* y (renderer3d-frame-artifact-width artifact))))))

; renderer3d-frame-object-at : renderer3d-frame-artifact? integer? integer? -> (or/c #f any/c)
;; Returns a backend-neutral object/source token when object-id was requested.
(define (renderer3d-frame-object-at artifact x y)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-object-at "renderer3d-frame-artifact?" artifact))
  (unless (and (exact-nonnegative-integer? x) (< x (renderer3d-frame-artifact-width artifact))
               (exact-nonnegative-integer? y) (< y (renderer3d-frame-artifact-height artifact)))
    (raise-argument-error 'renderer3d-frame-object-at "in-bounds pixel coordinates" (vector x y)))
  (define values (renderer3d-frame-artifact-object-id-snapshot artifact))
  (and values (vector-ref values (+ x (* y (renderer3d-frame-artifact-width artifact))))))

; renderer3d-frame-project : renderer3d-frame-artifact? vec3? -> (or/c #f vec2?)
;; Projects through the exact camera and aspect ratio used for this artifact.
(define (renderer3d-frame-project artifact point)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-project "renderer3d-frame-artifact?" artifact))
  (unless (vec3? point)
    (raise-argument-error 'renderer3d-frame-project "vec3?" point))
  (camera3d-project (renderer3d-frame-artifact-camera artifact) point
                    #:aspect (/ (renderer3d-frame-artifact-width artifact)
                                (renderer3d-frame-artifact-height artifact))))
