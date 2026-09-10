#lang racket/base

;; Typography is geometry- and pixel-affecting project configuration.  These
;; tests exercise the persistent cache through the public section renderer,
;; including callers that deliberately provide their own authored source key.

(require racket/file
         rackunit
         "../authoring.rkt"
         "../main.rkt"
         "../render.rkt"
         "../private/render-typography-context.rkt")

(define (body-theme id size #:display-name [display-name "Typography cache"]
                    #:provenance [provenance #f])
  (typography-theme
   #:id id
   #:display-name display-name
   #:provenance provenance
   #:extends animate-typography-theme
   #:styles
   (hash 'body
         (text-style-update
          (typography-ref animate-typography-theme 'body)
          #:font-size size))))

(define timeline
  (make-authored-timeline
   (scene-wait
    (scene-add
     (make-scene #:camera (make-camera #:width 160 #:height 90 #:world-width 8))
     (body-text "Persistent typography cache" #:id 'body #:center origin))
    1)
   #:sections (list (section 'only 0 1))))

(module+ test
  (define medium (body-theme 'medium 1/2))
  (define medium-metadata
    (body-theme 'medium-description 1/2
                #:display-name "Same appearance, new name"
                #:provenance 'documentation-revision))
  (define large (body-theme 'large 4/5))
  ;; The theme fingerprint describes authored appearance only. A renderer
  ;; semantics change is isolated in the resolver version, so its cache
  ;; namespace must differ even for the exact same theme snapshot.
  (define current-context (make-render-typography-context medium))
  (define resolver-2-context
    (render-typography-context medium
                               (typography-theme-fingerprint medium)
                               2))
  (check-equal? (render-typography-context-resolver-version current-context) 3)
  (check-equal? (render-typography-context-appearance-fingerprint current-context)
                (render-typography-context-appearance-fingerprint resolver-2-context))
  (check-not-equal?
   (automatic-section-cache-key timeline (timeline-section timeline 'only)
                                #:fps 1 #:camera #f #:renderers '()
                                #:typography-context resolver-2-context
                                #:asset-files '())
   (automatic-section-cache-key timeline (timeline-section timeline 'only)
                                #:fps 1 #:camera #f #:renderers '()
                                #:typography-context current-context
                                #:asset-files '()))
  (define root (make-temporary-file "animate-typography-section-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define first
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:typography medium #:cache-key 'source-v1))
     (check-false (section-render-report-cache-hit? first))
     (define reuse
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:typography medium #:cache-key 'source-v1))
     (check-true (section-render-report-cache-hit? reuse))
     ;; Display name and provenance are intentionally outside a typography
     ;; appearance fingerprint, so the concrete frame stays reusable.
     (define metadata-reuse
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:typography medium-metadata #:cache-key 'source-v1))
     (check-true (section-render-report-cache-hit? metadata-reuse))
     ;; A larger body role changes both text geometry and pixels.  It must miss
     ;; despite retaining the same explicit authored source cache key.
     (define changed
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:typography large #:cache-key 'source-v1))
     (check-false (section-render-report-cache-hit? changed))
     (define changed-reuse
       (render-timeline-section/report!
        timeline 'only root #:fps 1 #:typography large #:cache-key 'source-v1))
     (check-true (section-render-report-cache-hit? changed-reuse))
     ;; The public section APIs accept either a typography theme or a prepared
     ;; immutable context. Supplying a context alone must not collide with a
     ;; hidden non-false default theme.
     (check-not-false
      (render-timeline-section!
       timeline 'only root #:fps 1 #:cache-key 'default-typography))
     (define context-only
       (make-render-typography-context medium))
     (check-not-false
      (render-timeline-section!
       timeline 'only root #:fps 1 #:typography-context context-only
       #:cache-key 'context-only))
     (check-not-false
      (render-timeline-section/report!
       timeline 'only root #:fps 1 #:typography-context context-only
       #:cache-key 'context-only-report))
     (check-exn
      exn:fail:contract?
      (lambda ()
        (render-timeline-section!
         timeline 'only root #:fps 1 #:typography medium
         #:typography-context context-only #:cache-key 'ambiguous)))
     (check-exn
      exn:fail:contract?
      (lambda ()
        (render-timeline-section/report!
         timeline 'only root #:fps 1 #:typography medium
         #:typography-context context-only #:cache-key 'ambiguous-report))))
   (lambda () (delete-directory/files root))))
