#lang racket/base

;; Immutable, random-access presentation timelines. No frame-to-frame updaters.
(require racket/list (only-in racket/math pi)
         "private/math.rkt" "private/data.rkt" "theme.rkt")
(provide make-geometry-timeline sample-geometry-timeline geometry-timeline-narration-at
         default-geometry-timing)

(define (initial-state program)
  (for/hash ([n (in-list (geometry-program-nodes program))])
    (values (geometry-node-id n) (presentation (geometry-node-given? n)
                                             (eq? (geometry-node-type n) 'Point) #f))))
(define (apply-action state action)
  (for/fold ([state state]) ([id (in-list (geometry-action-targets action))])
    (define old (hash-ref state id))
    (define next
      (case (geometry-action-kind action)
        [(reveal show) (struct-copy presentation old [shown? #t])]
        [(hide) (struct-copy presentation old [shown? #f])]
        [(show-label) (struct-copy presentation old [label? #t])]
        [(hide-label) (struct-copy presentation old [label? #f])]
        [(deemphasize) (struct-copy presentation old [secondary? #t])]
        [(normalize) (struct-copy presentation old [secondary? #f])]
        [(highlight) old]
        [else (geometry-error 'timeline "unexpected action ~a" (geometry-action-kind action))]))
    (hash-set state id next)))
(define (leaf-actions action)
  (if (eq? (geometry-action-kind action) 'together) (geometry-action-payload action) (list action)))
(define (revealed-ids actions)
  (append-map (lambda (a)
                (case (geometry-action-kind a)
                  [(reveal) (geometry-action-targets a)]
                  [(together) (revealed-ids (geometry-action-payload a))]
                  [else '()])) actions))

(define default-geometry-timing (geometry-timing 0.6 0.7 0.9 0.5))

(define (make-geometry-timeline realization #:theme [theme default-geometry-theme]
                                #:read-delay [read-delay #f]
                                #:action-duration [action-duration #f]
                                #:step-pause [step-pause #f]
                                #:opening-pause [opening-pause #f]
                                #:hold [hold #f] #:opening-hold [opening-hold #f])
  (unless (and (geometry-realization? realization) (geometry-theme? theme)
               (or (not read-delay) (and (finite-real? read-delay) (>= read-delay 0)))
               (or (not action-duration) (and (finite-real? action-duration) (> action-duration 0)))
               (or (not step-pause) (and (finite-real? step-pause) (>= step-pause 0)))
               (or (not opening-pause) (and (finite-real? opening-pause) (>= opening-pause 0)))
               (or (not hold) (and (finite-real? hold) (>= hold 0)))
               (or (not opening-hold) (and (finite-real? opening-hold) (>= opening-hold 0))))
    (geometry-error 'make-geometry-timeline "invalid realization, theme or duration"))
  (define program (geometry-realization-program realization))
  (define base-timing (or (geometry-program-timing program) default-geometry-timing))
  (define effective-opening-pause (cond [opening-hold opening-hold] [opening-pause opening-pause]
                                        [else (geometry-timing-opening-pause base-timing)]))
  (define effective-read-delay (if read-delay read-delay (geometry-timing-read-delay base-timing)))
  (define effective-action-duration (if action-duration action-duration (geometry-timing-action-duration base-timing)))
  (define effective-step-pause (cond [hold hold] [step-pause step-pause]
                                     [else (geometry-timing-step-pause base-timing)]))
  (for ([s (in-list (geometry-program-styles program))]) (validate-object-style (cdr s)))
  (define initial
    (for/fold ([state (initial-state program)]) ([a (in-list (geometry-program-initial program))])
      (apply-action state a)))
  (define state initial)
  (define time effective-opening-pause)
  (define events '())
  (define cues '())
  (define (add-event! actions duration)
    (define next (foldl (lambda (a s) (apply-action s a)) state actions))
    (define meaningful? (or (not (equal? next state))
                            (ormap (lambda (a) (eq? (geometry-action-kind a) 'highlight)) actions)))
    (when meaningful?
      (set! events (append events (list (geometry-event time (+ time duration) actions state next))))
      (set! state next)
      (set! time (+ time duration))))
  (define (visit-step! step)
    (define start time)
    (define read-delay*
      (cond [(hash-has-key? (geometry-step-timing step) 'read-delay)
             (hash-ref (geometry-step-timing step) 'read-delay)]
            [(geometry-step-narration step) effective-read-delay]
            [else 0]))
    (define action-duration* (hash-ref (geometry-step-timing step) 'duration effective-action-duration))
    (define step-pause* (hash-ref (geometry-step-timing step) 'pause effective-step-pause))
    (define actions (geometry-step-actions step))
    (define new-ids (revealed-ids actions))
    (set! time (+ time read-delay*))
    ;; Configure labels before a newly introduced point appears, avoiding a
    ;; one-frame label flash for a same-step hide-label command.
    (for ([a (in-list (append-map leaf-actions actions))]
          #:when (memq (geometry-action-kind a) '(show-label hide-label)))
      (define newborn (filter (lambda (id) (and (memq id new-ids)
                                                (not (presentation-shown? (hash-ref state id)))))
                              (geometry-action-targets a)))
      (unless (null? newborn)
        (define change (struct-copy geometry-action a [targets newborn]))
        ;; A zero-duration state boundary is represented explicitly, so random
        ;; access before this step still sees the earlier label preference.
        (define next (apply-action state change))
        (set! events (append events (list (geometry-event time time (list change) state next))))
        (set! state next)))
    (for ([a (in-list actions)])
      (if (eq? (geometry-action-kind a) 'expanded)
          (for-each visit-step! (geometry-action-payload a))
          (add-event! (leaf-actions a) action-duration*)))
    (set! time (+ time step-pause*))
    (when (geometry-step-narration step)
      (set! cues (append cues (list (geometry-cue start time (geometry-step-narration step)))))))
  (for-each visit-step! (geometry-program-steps program))
  ;; Keep even an empty exposition a valid nonzero animate scene.
  (geometry-timeline realization theme events cues initial state (if (> time 0) time 0.01)))

(define (unit x) (max 0 (min 1 x)))
(define (smooth x) (define u (unit x)) (* u u (- 3 (* 2 u))))
(define (bit b) (if b 1 0))
(define (lerp a b p)
  (cond [(or (= a b) (= p 0)) a] [(= p 1) b] [else (+ a (* (- b a) p))]))
(define (appearance state)
  (geometry-appearance (bit (presentation-shown? state))
                       (if (and (presentation-shown? state) (presentation-label? state)) 1 0)
                       1 (bit (presentation-secondary? state)) 0))
(define (geometry-timeline-narration-at timeline t)
  ;; The shortest enclosing cue is the expanded helper's local explanation.
  (define matches (filter (lambda (c) (and (<= (geometry-cue-start c) t)
                                            (or (< t (geometry-cue-end c))
                                                (and (= t (geometry-timeline-duration timeline))
                                                     (= t (geometry-cue-end c))))))
                          (geometry-timeline-cues timeline)))
  (and (pair? matches)
       (geometry-cue-text (argmin (lambda (c) (- (geometry-cue-end c) (geometry-cue-start c))) matches))))
(define (sample-geometry-timeline timeline t)
  (unless (and (geometry-timeline? timeline) (finite-real? t))
    (geometry-error 'sample-geometry-timeline "expected a timeline and finite time"))
  (define time (max 0 (min t (geometry-timeline-duration timeline))))
  (define state (geometry-timeline-initial timeline))
  (define active #f)
  (for ([event (in-list (geometry-timeline-events timeline))])
    (cond [(<= (geometry-event-end event) time) (set! state (geometry-event-after event))]
          [(and (<= (geometry-event-start event) time) (< time (geometry-event-end event)))
           (set! state (geometry-event-before event)) (set! active event)]))
  (define base (for/hash ([(id s) (in-hash state)]) (values id (appearance s))))
  (define result
    (if (not active) base
        (let* ([progress (/ (- time (geometry-event-start active))
                            (- (geometry-event-end active) (geometry-event-start active)))]
               [p (smooth progress)])
          (for/fold ([sample base]) ([action (in-list (geometry-event-actions active))])
            (for/fold ([sample sample]) ([id (in-list (geometry-action-targets action))])
              (define before (hash-ref (geometry-event-before active) id))
              (define after (hash-ref (geometry-event-after active) id))
              (define showing? (and (not (presentation-shown? before)) (presentation-shown? after)))
              (define kind (geometry-action-kind action))
              (define draw? (and showing? (eq? kind 'reveal)))
              (define opacity (if draw? 1 (lerp (bit (presentation-shown? before))
                                                (bit (presentation-shown? after)) p)))
              (define label-start (if (and (presentation-shown? before) (presentation-label? before)) 1 0))
              (define label-end (if (and (presentation-shown? after) (presentation-label? after)) 1 0))
              (define label-progress (if draw? (smooth (/ (- progress 0.35) 0.65)) p))
              (hash-set sample id
                        (geometry-appearance
                         opacity (lerp label-start label-end label-progress)
                         (if draw? p 1)
                         (lerp (bit (presentation-secondary? before)) (bit (presentation-secondary? after)) p)
                         (if (and (eq? kind 'highlight) (presentation-shown? before))
                             (* (sin (* pi progress)) (sin (* pi progress))) 0))))))))
  (geometry-frame time result (geometry-timeline-narration-at timeline time)))
