#lang racket/base

;; Pure effective narration, shared by subtitle export and the render boundary.
;; Does not import Animate, a renderer, fonts, or a file format implementation.
(require racket/list "private/math.rkt" "private/data.rkt" "timeline.rkt")
(provide geometry-caption-cues)

;; geometry-caption-cues : geometry-timeline? -> (listof geometry-cue?)
;; The visual sampler gives precedence to the shortest enclosing cue (stable
;; source order breaks ties). Sample each elementary interval with that same
;; policy. Adjacent identical captions merge, but never across a silent gap.
;; Silent/zero-duration steps do not create zero-duration subtitle entries.
(define (geometry-caption-cues timeline)
  (unless (geometry-timeline? timeline)
    (raise-argument-error 'geometry-caption-cues "geometry-timeline?" timeline))
  (define duration (geometry-timeline-duration timeline))
  (define cues (geometry-timeline-cues timeline))
  (for ([cue (in-list cues)])
    (unless (and (geometry-cue? cue)
                 (finite-real? (geometry-cue-start cue))
                 (finite-real? (geometry-cue-end cue))
                 (<= 0 (geometry-cue-start cue) (geometry-cue-end cue) duration)
                 (or (not (geometry-cue-text cue)) (string? (geometry-cue-text cue))))
      (raise-arguments-error 'geometry-caption-cues
                             "cue must lie within the timeline and contain text or #f"
                             "cue" cue "duration" duration)))
  (define boundaries
    (sort (remove-duplicates
           (append-map (lambda (c) (list (geometry-cue-start c) (geometry-cue-end c)))
                       cues) =) <))
  (define reversed '())
  (for ([from (in-list boundaries)]
        [to (in-list (if (null? boundaries) '() (cdr boundaries)))])
    (define text (geometry-timeline-narration-at timeline (/ (+ from to) 2)))
    (when text
      (if (and (pair? reversed) (equal? text (geometry-cue-text (car reversed)))
               (= from (geometry-cue-end (car reversed))))
          (set! reversed (cons (geometry-cue (geometry-cue-start (car reversed)) to text)
                               (cdr reversed)))
          (set! reversed (cons (geometry-cue from to text) reversed)))))
  (reverse reversed))
