#lang racket/base

;; Pure review planning. No GUI, PNG generation, files, FFmpeg, or frame-grid
;; rounding. The authoritative step boundaries are recorded by timeline.rkt.
(require racket/list racket/format racket/string
         "core.rkt" "private/reveal.rkt")
(provide (struct-out geometry-review-sample)
         (struct-out geometry-review-step)
         make-geometry-review-plan geometry-review-samples
         geometry-review-span-reviewable?)

;; Most steps have three samples: read, during, settled. Steps containing a
;; compass circle reveal get dedicated samples for the movable carrier's pickup,
;; source attention pulse, transport, target attention pulse, and sweep.
(struct geometry-review-sample (phase time filename frame note) #:transparent)
(struct geometry-review-step (number span caption samples notes) #:transparent)

;; Timeline reveal progress is smoothstep(raw-event-progress), so review samples
;; that target a semantic reveal phase must invert that easing before choosing
;; the timestamp. Bisection is deterministic and avoids depending on a numeric
;; root finder or a fragile closed-form branch.
(define (smooth x)
  (define u (max 0 (min 1 x)))
  (* u u (- 3 (* 2 u))))
(define (inverse-smooth y)
  (define target (max 0 (min 1 y)))
  (let loop ([lo 0.0] [hi 1.0] [n 0])
    (if (>= n 60)
        (/ (+ lo hi) 2.0)
        (let* ([mid (/ (+ lo hi) 2.0)]
               [value (smooth mid)])
          (if (< value target)
              (loop mid hi (add1 n))
              (loop lo mid (add1 n)))))))

(define (prefix? a b)
  (and (<= (length a) (length b)) (equal? a (take b (length a)))))
(define (span-caption span spans)
  (or (geometry-step-span-narration span)
      (for/fold ([text #f]) ([other (in-list spans)]
                            #:when (and (geometry-step-span-narration other)
                                        (prefix? (geometry-step-span-path other)
                                                 (geometry-step-span-path span))))
        (geometry-step-span-narration other))))

(define (cleanup-action? action)
  (case (geometry-action-kind action)
    [(hide hide-label deemphasize normalize) #t]
    [(together) (andmap cleanup-action? (geometry-action-payload action))]
    [else #f]))

;; Silent maintenance steps are useful in the movie but usually add only blank
;; or duplicate rows to an audit bundle. Narrated steps always remain. Silent
;; reveals/highlights/shows remain because they introduce visible information.
(define (geometry-review-span-reviewable? span spans #:include-cleanup? [include-cleanup? #f])
  (or include-cleanup?
      (geometry-step-span-narration span)
      (let ([events (geometry-step-span-events span)])
        (and (pair? events)
             (for/or ([event (in-list events)])
               (for/or ([action (in-list (geometry-event-actions event))])
                 (not (cleanup-action? action))))))))

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

(define (event-compass? event compass-reveal-target?)
  (for/or ([action (in-list (geometry-event-actions event))])
    (and (eq? (geometry-action-kind action) 'reveal)
         (for/or ([id (in-list (geometry-action-targets action))])
           (compass-reveal-target? id)))))

(define (make-geometry-review-plan timeline #:expanded? [expanded? #t]
                                  #:include-cleanup? [include-cleanup? #f])
  (unless (geometry-timeline? timeline)
    (raise-argument-error 'make-geometry-review-plan "geometry-timeline?" timeline))
  (unless (boolean? expanded?)
    (raise-argument-error 'make-geometry-review-plan "boolean?" expanded?))
  (unless (boolean? include-cleanup?)
    (raise-argument-error 'make-geometry-review-plan "boolean?" include-cleanup?))
  (define spans (geometry-timeline-steps timeline))
  (define realization (geometry-timeline-realization timeline))
  (define program (geometry-realization-program realization))
  (define environment (geometry-realization-values realization))
  (define node-table
    (for/hash ([node (in-list (geometry-program-nodes program))])
      (values (geometry-node-id node) node)))
  (define (compass-reveal-target? id)
    (and (hash-has-key? node-table id)
         (eq? (geometry-node-type (hash-ref node-table id)) 'Circle)
         (call-with-values (lambda () (resolve-circle-reveal program id environment))
           (lambda (mode _source) (eq? mode 'compass)))))
  (define selected
    (filter (lambda (s) (and (not (geometry-step-span-generated? s))
                            (or expanded? (= (length (geometry-step-span-path s)) 1))
                            (geometry-review-span-reviewable? s spans
                                                             #:include-cleanup? include-cleanup?)))
            spans))
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
    (define compass-event
      (for/first ([event (in-list active)] #:when (event-compass? event compass-reveal-target?)) event))
    (define read-time (/ (+ start action-start) 2))
    (define mid-time (during-time active (/ (+ action-start action-end) 2)))
    (define settled-time (/ (+ action-end end) 2))
    (define instantaneous? (= start end))
    (define prefix (format "step-~a" (~r number #:min-width 3 #:pad-string "0")))
    (define (sample phase t frame note)
      (geometry-review-sample phase t (format "~a-~a.png" prefix phase) frame note))
    (define samples
      (if compass-event
          (let* ([event-start (geometry-event-start compass-event)]
                 [event-duration (- (geometry-event-end compass-event) event-start)]
                 [at-reveal
                  (lambda (reveal-progress)
                    (+ event-start
                       (* event-duration (inverse-smooth reveal-progress))))])
            (list
             (sample 'read read-time
                     (state-frame (geometry-step-span-before span) read-time caption)
                     (if (= start action-start)
                         "No reading interval: exact pre-action state (boundary snapshot)."
                         "Middle of the reading interval; the figure is unchanged."))
             (sample 'pickup (at-reveal compass-review-pickup-progress)
                     (sample-geometry-timeline timeline (at-reveal compass-review-pickup-progress))
                     "The movable carrier is being drawn directly over the source measure.")
             (sample 'source-attention (at-reveal compass-review-source-attention-progress)
                     (sample-geometry-timeline timeline (at-reveal compass-review-source-attention-progress))
                     "The carrier has lifted onto a nearby parallel and receives its first attention pulse.")
             (sample 'transport (at-reveal compass-review-transport-progress)
                     (sample-geometry-timeline timeline (at-reveal compass-review-transport-progress))
                     "The copied length is moving rigidly from the source toward the new centre.")
             (sample 'target-attention (at-reveal compass-review-target-attention-progress)
                     (sample-geometry-timeline timeline (at-reveal compass-review-target-attention-progress))
                     "The carrier has arrived at the new centre and receives its second attention pulse.")
             (sample 'sweep (at-reveal compass-review-sweep-progress)
                     (sample-geometry-timeline timeline (at-reveal compass-review-sweep-progress))
                     "The anchored carrier is sweeping the circumference while the circle is traced.")
             (sample 'settled settled-time
                     (state-frame (geometry-step-span-after span) settled-time caption)
                     (if (= action-end end)
                         "No ending pause: exact post-action state, before the next step (boundary snapshot)."
                         "Middle of the ending pause; all actions of this step are complete."))))
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
                       "Middle of the ending pause; all actions of this step are complete.")))))
    (geometry-review-step
     number span caption samples
     (append
      (if (zero? (geometry-step-span-id span)) '("Initial diagram: no authored steps.") '())
      (if instantaneous? '("Instantaneous step: boundary snapshots have no on-screen dwell time.") '())
      (if compass-event
          '("Compass circle reveal: this row includes dedicated pickup, source-attention, transport, target-attention, and sweep samples.")
          '())
      (if (geometry-step-span-expanded? span)
          '("Expanded overview. Child rows appear separately; action samples may show a child's caption.") '())
      (if (> (length active) 1)
          '("This step contains several actions; a single action sample does not show every transition.") '())))))

(define (geometry-review-samples plan)
  (unless (and (list? plan) (andmap geometry-review-step? plan))
    (raise-argument-error 'geometry-review-samples "list of geometry-review-step?" plan))
  (append-map geometry-review-step-samples plan))
