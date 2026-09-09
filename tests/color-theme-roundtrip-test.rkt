#lang racket/base

;;;
;;; Project Theme Datum Round-Trip Tests
;;;

(require racket/list
         rackunit
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../project.rkt")

(module+ test
  (define custom
    (color-theme #:id 'round-trip-theme
                 #:extends animate-dark-theme
                 #:provenance "themes/round-trip.rktd"))
  (define plan
    (plan-project
     (animate-project
      #:id 'round-trip
      #:source (scene-source (scene-wait (make-scene) 1))
      #:render (render-spec #:theme custom)
      #:output (output-spec #:root "media" #:name "round-trip"))))
  (define saved-theme
    (hash-ref (hash-ref (project-plan->datum plan) 'color-theme) 'datum))
  (define restored (datum->theme saved-theme))
  (check-equal? (theme->datum restored) saved-theme)
  (check-equal? (color-theme-fingerprint restored)
                (color-theme-fingerprint custom))
  (check-equal? (color-theme-provenance restored)
                "themes/round-trip.rktd")

  ;; Presentation and serialized palette order are canonical rather than an
  ;; accidental record of which parent introduced a custom key first.
  (define a-first
    (color-palette #:id 'a-first #:extends animate-palette
                   #:colors (hash 'a-custom "#123456")))
  (define a-then-z
    (color-palette #:id 'a-then-z #:extends a-first
                   #:colors (hash 'z-custom "#654321")))
  (define z-first
    (color-palette #:id 'z-first #:extends animate-palette
                   #:colors (hash 'z-custom "#654321")))
  (define z-then-a
    (color-palette #:id 'z-then-a #:extends z-first
                   #:colors (hash 'a-custom "#123456")))
  (check-equal? (palette-keys a-then-z) (palette-keys z-then-a))
  (check-equal? (take-right (palette-keys a-then-z) 2) '(a-custom z-custom))
  (define first-theme
    (color-theme #:id 'first #:extends animate-light-theme #:palette a-then-z))
  (define second-theme
    (color-theme #:id 'second #:extends animate-light-theme #:palette z-then-a))
  (check-equal? (color-theme-fingerprint first-theme)
                (color-theme-fingerprint second-theme))
  (check-equal? (color-theme-fingerprint first-theme)
                (color-theme-fingerprint (datum->theme (theme->datum first-theme)))))
