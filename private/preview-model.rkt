#lang racket/base

;;;
;;; Headless Preview Model
;;;

;; Immutable descriptions of what a preview session is showing.  This module
;; deliberately has no GUI, threads, bitmap cache, or filesystem effects.  A
;; frame sample denotes an encoded-video grid point; a time sample denotes an
;; arbitrary exact inspection point, including the scene's final endpoint.

(require racket/list
         "authoring-timeline.rkt"
         "camera.rkt"
         "frame-renderer.rkt"
         "geometry.rkt"
         (only-in "pict-adapter.rkt" default-pict-renderers)
         "pict-renderer.rkt"
         "scene.rkt")

(provide (struct-out preview-render-spec)
         (struct-out frame-sample)
         (struct-out time-sample)
         (struct-out preview-document)
         (struct-out preview-frame-key)
         make-preview-render-spec
         make-preview-document
         preview-source?
         preview-source-scene
         preview-document-frame-count
         preview-document-section-names
         preview-document-section-frame-indices
         preview-document-section-cues
         preview-frame-sample-valid?
         preview-normalize-frame-sample
         preview-normalize-time-sample
         preview-final-sample
         preview-sample-time
         preview-sample-frame-index
         preview-render-spec-id
         make-preview-frame-key)


;;;
;;; Semantic Values
;;;

;; The renderer list is intentionally retained as a value rather than converted
;; to a lossy hash.  A document/render generation establishes the cache
;; namespace whenever callers replace arbitrary custom renderers.
(struct preview-render-spec (fps camera renderers pixel-scale supersample)
  #:transparent)

;; frame-sample is the authoritative playback identity.  Its time is always
;; calculated as index/fps, never accumulated from preceding samples.
(struct frame-sample (frame-index fps)
  #:transparent)

;; time-sample is for exact inspection and includes endpoints that do not occur
;; on the encoded frame grid.
(struct time-sample (time)
  #:transparent)

;; `timeline` is #f for a plain scene and retains authored metadata otherwise.
;; The source field is the exact source supplied by the caller, which is useful
;; to APIs that need to report whether section navigation is available.
(struct preview-document (source scene timeline generation label)
  #:transparent)

;; render-spec-id is the complete immutable render-spec value.  We do not hash
;; arbitrary procedures or renderer objects: a configuration replacement is
;; instead represented by render-generation.
(struct preview-frame-key (generation render-generation sample render-spec-id)
  #:transparent)


;;;
;;; Construction
;;;

(define (make-preview-render-spec #:fps [fps 30]
                                  #:camera [camera #f]
                                  #:renderers [renderers default-pict-renderers]
                                  #:pixel-scale [pixel-scale 1]
                                  #:supersample [supersample 1])
  (check-fps 'make-preview-render-spec fps)
  (unless (or (not camera) (camera? camera))
    (raise-argument-error 'make-preview-render-spec "(or/c camera? #f)" camera))
  (unless (and (list? renderers) (andmap pict-renderer? renderers))
    (raise-argument-error
     'make-preview-render-spec
     "(listof pict-renderer?)"
     renderers))
  (check-positive-real 'make-preview-render-spec "pixel-scale" pixel-scale)
  (unless (exact-positive-integer? supersample)
    (raise-argument-error
     'make-preview-render-spec
     "exact-positive-integer?"
     supersample))
  (preview-render-spec fps camera renderers pixel-scale supersample))

(define (make-preview-document source #:generation [generation 0] #:label [label #f])
  (unless (preview-source? source)
    (raise-argument-error 'make-preview-document "(or/c scene? authored-timeline?)" source))
  (unless (exact-nonnegative-integer? generation)
    (raise-argument-error
     'make-preview-document
     "exact-nonnegative-integer?"
     generation))
  (unless (or (not label) (string? label) (symbol? label))
    (raise-argument-error 'make-preview-document "(or/c #f string? symbol?)" label))
  (preview-document source
                    (preview-source-scene source)
                    (and (authored-timeline? source) source)
                    generation
                    label))

(define (preview-source? value)
  (or (scene? value) (authored-timeline? value)))

(define (preview-source-scene source)
  (cond
    [(scene? source) source]
    [(authored-timeline? source) (authored-timeline-scene source)]
    [else
     (raise-argument-error 'preview-source-scene "(or/c scene? authored-timeline?)" source)]))


;;;
;;; Sample Identity and Bounds
;;;

(define (preview-document-frame-count document render-spec)
  (check-preview-document 'preview-document-frame-count document)
  (check-preview-render-spec 'preview-document-frame-count render-spec)
  (scene-frame-count (preview-document-scene document)
                     #:fps (preview-render-spec-fps render-spec)))

(define (preview-frame-sample-valid? document sample)
  (and (preview-document? document)
       (frame-sample? sample)
       (exact-nonnegative-integer? (frame-sample-frame-index sample))
       (exact-positive-integer? (frame-sample-fps sample))
       (< (frame-sample-frame-index sample)
          (scene-frame-count (preview-document-scene document)
                             #:fps (frame-sample-fps sample)))))

;; Public preview seeking clamps.  A zero-duration scene has no encoded frame,
;; so its meaningful clamped result is its exact endpoint time sample.
(define (preview-normalize-frame-sample document frame-index render-spec)
  (check-preview-document 'preview-normalize-frame-sample document)
  (unless (exact-integer? frame-index)
    (raise-argument-error
     'preview-normalize-frame-sample
     "exact-integer?"
     frame-index))
  (check-preview-render-spec 'preview-normalize-frame-sample render-spec)
  (define fps (preview-render-spec-fps render-spec))
  (define count (preview-document-frame-count document render-spec))
  (cond
    [(zero? count) (preview-final-sample document)]
    [else
     (frame-sample (min (max frame-index 0) (sub1 count)) fps)]))

(define (preview-normalize-time-sample document time)
  (check-preview-document 'preview-normalize-time-sample document)
  (check-finite-real 'preview-normalize-time-sample "time" time)
  (time-sample
   (min (max time 0) (scene-duration (preview-document-scene document)))))

(define (preview-final-sample document)
  (check-preview-document 'preview-final-sample document)
  (time-sample (scene-duration (preview-document-scene document))))

(define (preview-sample-time document sample)
  (check-preview-document 'preview-sample-time document)
  (cond
    [(frame-sample? sample)
     (unless (preview-frame-sample-valid? document sample)
       (raise-arguments-error
        'preview-sample-time
        "frame sample is outside this preview document"
        "sample" sample))
     (frame-index->time (frame-sample-frame-index sample)
                        #:fps (frame-sample-fps sample))]
    [(time-sample? sample)
     (define time (time-sample-time sample))
     (check-finite-real 'preview-sample-time "sample time" time)
     (define duration (scene-duration (preview-document-scene document)))
     (unless (<= 0 time duration)
       (raise-arguments-error
        'preview-sample-time
        "time sample is inside this preview document"
        "sample" sample
        "duration" duration))
     time]
    [else
     (raise-argument-error 'preview-sample-time "(or/c frame-sample? time-sample?)" sample)]))

(define (preview-sample-frame-index sample)
  (and (frame-sample? sample) (frame-sample-frame-index sample)))


;;;
;;; Timeline Metadata
;;;

(define (preview-document-section-names document)
  (check-preview-document 'preview-document-section-names document)
  (define timeline (preview-document-timeline document))
  (if timeline
      (timeline-section-names timeline)
      '()))

(define (preview-document-section-frame-indices document name render-spec)
  (check-preview-document 'preview-document-section-frame-indices document)
  (check-preview-render-spec 'preview-document-section-frame-indices render-spec)
  (define timeline (preview-document-timeline document))
  (unless timeline
    (raise-arguments-error
     'preview-document-section-frame-indices
     "preview document has an authored timeline"
     "document" document))
  (timeline-section-frame-indices timeline name #:fps (preview-render-spec-fps render-spec)))

(define (preview-document-section-cues document name)
  (check-preview-document 'preview-document-section-cues document)
  (define timeline (preview-document-timeline document))
  (unless timeline
    (raise-arguments-error
     'preview-document-section-cues
     "preview document has an authored timeline"
     "document" document))
  (timeline-section-cues timeline name))


;;;
;;; Render Keys
;;;

(define (preview-render-spec-id render-spec)
  (check-preview-render-spec 'preview-render-spec-id render-spec)
  render-spec)

(define (make-preview-frame-key document render-generation sample render-spec)
  (check-preview-document 'make-preview-frame-key document)
  (unless (exact-nonnegative-integer? render-generation)
    (raise-argument-error
     'make-preview-frame-key
     "exact-nonnegative-integer?"
     render-generation))
  (check-preview-render-spec 'make-preview-frame-key render-spec)
  ;; Validate now, so an invalid key cannot be inserted into a cache and later
  ;; fail only when a worker happens to draw it.
  (preview-sample-time document sample)
  (preview-frame-key (preview-document-generation document)
                     render-generation
                     sample
                     (preview-render-spec-id render-spec)))


;;;
;;; Validation
;;;

(define (check-preview-document who value)
  (unless (preview-document? value)
    (raise-argument-error who "preview-document?" value)))

(define (check-preview-render-spec who value)
  (unless (preview-render-spec? value)
    (raise-argument-error who "preview-render-spec?" value)))

(define (check-fps who fps)
  (unless (exact-positive-integer? fps)
    (raise-argument-error who "exact-positive-integer?" fps)))

(define (check-positive-real who label value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real" label value)))

(define (check-finite-real who label value)
  (unless (finite-real? value)
    (raise-arguments-error who "finite real" label value)))
