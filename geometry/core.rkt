#lang racket/base

;; Headless mathematical authoring API. This module does not load animate,
;; pict, a GUI, TeX, or any rendering backend.
(require "dsl.rkt" "private/math.rkt" "private/data.rkt"
         "layout.rkt" "theme.rkt" "timeline.rkt" "annotations.rkt")
(provide (all-from-out "dsl.rkt" "private/math.rkt" "private/data.rkt"
                       "layout.rkt" "theme.rkt" "timeline.rkt" "annotations.rkt")
         construction->timeline)

;; construction->timeline : geometry-program? ... -> geometry-timeline?
;; Realize all free geometry once, then compile the exposition independently.
(define (construction->timeline program
                                #:theme [theme default-geometry-theme]
                                #:view [view #f] #:aspect [aspect 16/9]
                                #:margin [margin 0.1] #:padding [padding 0.45]
                                #:samples [samples 256]
                                #:givens [givens (hash)] #:choices [choices (hash)]
                                #:read-delay [read-delay #f]
                                #:action-duration [action-duration #f]
                                #:step-pause [step-pause #f]
                                #:opening-pause [opening-pause #f]
                                #:hold [hold #f] #:opening-hold [opening-hold #f])
  (make-geometry-timeline
   (realize-construction program #:view view #:aspect aspect #:margin margin
                        #:padding padding #:samples samples #:givens givens #:choices choices)
   #:theme theme #:read-delay read-delay #:action-duration action-duration
   #:step-pause step-pause #:opening-pause opening-pause #:hold hold #:opening-hold opening-hold))
