#lang racket/base

;; Pure review planning. No GUI, PNG generation, files, FFmpeg, or frame-grid
;; rounding. The authoritative step boundaries are recorded by timeline.rkt.
(require racket/list racket/format racket/string
         "core.rkt")
(provide (struct-out geometry-review-sample)
         (struct-out geometry-review-step)
         make-geometry-review-plan geometry-review-samples)

;; Each step has exactly three samples. frame is ready for the native visual
;; sampler; its layout still comes from the complete, unmodified timeline.
(struct geometry-review-sample (phase time filename frame note) #:transparent)
(struct geometry-review-step (number span caption samples notes) #:transparent)

(define (prefix? a b)
  (and (<= (length a) (length b)) (equal? a (take b (length a)))))
(define (span-caption span spans)
  (or (geometry-step-span-narration span)
      (for/fold ([text #f]) ([other (in-list spans)]
                            #:when (and (geometry-step-span-narration other)
                                        (prefix? (geometry-step-span-path other)
                                                 (geometry-step-span-path span))))
        (geometry-step-span-narration other))))
(define (state-frame state t text)
  (geometry-frame
   t
   (for/hash ([(id p) (in-hash state)])
     (values id
             (geometry-appearance
              (if (presentation-shown? p) 1 0)
              (if (and (presentation-shown? p) (presentation-label? p)) 1 0)
              1 (if (presentation-secondary? p) 1 0) 0)))
   text))

;; Skip pauses, then choose the midpoint of accumulated positive-duration
;; actions. For an even number of equal actions the midpoint is a boundary:
;; choose the middle of the next action, never a blank boundary frame.
(define (during-time events fallback)
  (define active (filter (lambda (e) (< (geometry-event-start e) (geometry-event-end e))) events))
  (cond [(null? active) fallback]
        [else
         (define halfway (/ (for/sum ([e (in-list active)])
                              (- (geometry-event-end e) (geometry-event-start e))) 2))
         (let loop ([rest active] [remaining halfway])
           (define e (car rest))
           (define duration (- (geometry-event-end e) (geometry-event-start e)))
           (define epsilon (* 1e-9 (max 1 duration)))
           (cond [(and (> remaining (+ duration epsilon)) (pair? (cdr rest)))
                  (loop (cdr rest) (- remaining duration))]
                 [(and (>= remaining (- duration epsilon)) (pair? (cdr rest)))
                  (define next (cadr rest))
                  (/ (+ (geometry-event-start next) (geometry-event-end next)) 2)]
                 [(or (<= remaining epsilon) (>= remaining (- duration epsilon)))
                  (/ (+ (geometry-event-start e) (geometry-event-end e)) 2)]
                 [else (+ (geometry-event-start e) remaining)]))]))

(define (make-geometry-review-plan timeline #:expanded? [expanded? #t])
  (unless (geometry-timeline? timeline)
    (raise-argument-error 'make-geometry-review-plan "geometry-timeline?" timeline))
  (unless (boolean? expanded?)
    (raise-argument-error 'make-geometry-review-plan "boolean?" expanded?))
  (define spans (geometry-timeline-steps timeline))
  (define selected
    (filter (lambda (s) (and (not (geometry-step-span-generated? s))
                            (or expanded? (= (length (geometry-step-span-path s)) 1)))) spans))
  ;; A construction with no steps still has an initial diagram to inspect.
  (define review-spans
    (if (pair? selected) selected
        (list (geometry-step-span
               0 '(0) #f 0 0 0 (geometry-timeline-duration timeline) '()
               (geometry-timeline-initial timeline) (geometry-timeline-final timeline) #f #f))))
  (for/list ([span (in-list review-spans)] [number (in-naturals 1)])
    (define caption (span-caption span spans))
    (define start (geometry-step-span-start span))
    (define action-start (geometry-step-span-action-start span))
    (define action-end (geometry-step-span-action-end span))
    (define end (geometry-step-span-end span))
    (define active (filter (lambda (e) (< (geometry-event-start e) (geometry-event-end e)))
                           (geometry-step-span-events span)))
    (define read-time (/ (+ start action-start) 2))
    (define mid-time (during-time active (/ (+ action-start action-end) 2)))
    (define settled-time (/ (+ action-end end) 2))
    (define instantaneous? (= start end))
    (define prefix (format "step-~a" (~r number #:min-width 3 #:pad-string "0")))
    (define (sample phase t frame note)
      (geometry-review-sample phase t (format "~a-~a.png" prefix phase) frame note))
    (geometry-review-step
     number span caption
     (list
      (sample 'read read-time
              (state-frame (geometry-step-span-before span) read-time caption)
              (if (= start action-start)
                  "No reading interval: exact pre-action state (boundary snapshot)."
                  "Middle of the reading interval; the figure is unchanged."))
      (sample 'during mid-time
              (if (pair? active) (sample-geometry-timeline timeline mid-time)
                  (state-frame (geometry-step-span-before span) mid-time caption))
              (if (pair? active)
                  "Inside an action, selected from accumulated action time; pauses are excluded."
                  "No visual action: repeated unchanged state."))
      (sample 'settled settled-time
              (state-frame (geometry-step-span-after span) settled-time caption)
              (if (= action-end end)
                  "No ending pause: exact post-action state, before the next step (boundary snapshot)."
                  "Middle of the ending pause; all actions of this step are complete.")))
     (append
      (if (zero? (geometry-step-span-id span)) '("Initial diagram: no authored steps.") '())
      (if instantaneous? '("Instantaneous step: boundary snapshots have no on-screen dwell time.") '())
      (if (geometry-step-span-expanded? span)
          '("Expanded overview. Child rows appear separately; the during image may show a child's caption.") '())
      (if (> (length active) 1)
          '("This step contains several actions; one during image does not show every transition.") '())))))

(define (geometry-review-samples plan)
  (unless (and (list? plan) (andmap geometry-review-step? plan))
    (raise-argument-error 'geometry-review-samples "list of geometry-review-step?" plan))
  (append-map geometry-review-step-samples plan))
