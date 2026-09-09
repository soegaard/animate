#lang racket/base

;;;
;;; Project Theme Datum Round-Trip Tests
;;;

(require rackunit
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
                "themes/round-trip.rktd"))
