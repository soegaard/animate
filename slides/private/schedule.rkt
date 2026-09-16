#lang racket/base
(require racket/list racket/match "data.rkt" "check.rkt")
(provide compile-slide-clip clip-time initial-visible? visibility-at variant-at clock-at
         content-time unit progress active-variants slot-leaf-paths)
(define (unit x) (max 0 (min 1 x)))
(define (progress time start duration)
  (if (= duration 0) (if (< time start) 0 1) (unit (/ (- time start) duration))))
(define (initial-visible? initial path)
  (cond [(eq? initial 'visible) #t] [(eq? initial 'hidden) #f]
        [else (for/or ([target (in-list initial)]) (path-prefix? (selector-path target) path))]))
(define (slot-leaf-paths slots)
  (remove-duplicates
   (append-map (lambda (s) (append-map (lambda (v) (map prepared-leaf-path v)) (prepared-slot-variants s))) slots)
   equal?))
(define (visibility-at events initial path t)
  (for/fold ([opacity (if (initial-visible? initial path) 1 0)]) ([e (in-list events)]
              #:when (and (memq (event-kind e) '(reveal conceal))
                          (path-prefix? (event-target e) path) (>= t (event-start e))))
    (define p (if (eq? (event-effect e) 'instant) 1 (progress t (event-start e) (event-duration e))))
    (define from (hash-ref (event-from e) path opacity))
    (+ from (* p (- (event-to e) from)))))
(define (variant-at events slot time)
  (for/fold ([variant 0]) ([e (in-list events)]
              #:when (and (eq? (event-kind e) 'replace)
                          (eq? slot (car (event-target e)))
                          (>= time (+ (event-start e) (event-duration e)))))
    (event-to e)))
(define (active-variants events slot time)
  (define active
    (findf (lambda (e) (and (eq? (event-kind e) 'replace)
                            (eq? slot (car (event-target e)))
                            (<= (event-start e) time)
                            (< time (+ (event-start e) (event-duration e))))) events))
  (cond [active
         (define p (if (eq? (event-effect active) 'instant) 1 (progress time (event-start active) (event-duration active))))
         (list (cons (event-from active) (- 1 p)) (cons (event-to active) p))]
        [else (list (cons (variant-at events slot time) 1))]))
(define (content-time a value)
  (cond [(eq? value 'end) (asset-duration a)] [(eq? value 'start) 0]
        [(nonnegative-number? value)
         (unless (<= value (+ (asset-duration a) 1e-8))
           (slides-error 'content-time (list value) "embedded time exceeds its duration"))
         (min value (asset-duration a))]
        [(hash-ref (asset-cues a) value #f) => values]
        [else (slides-error 'unknown-content-cue (list value) "embedded content has no such named boundary")]))
(define (clock-at events slot variant a time hold?)
  (define reset
    (for/fold ([reset -inf.0]) ([e (in-list events)]
                #:when (and (eq? (event-kind e) 'replace) (eq? slot (car (event-target e)))
                            (= variant (event-to e)) (<= (event-start e) time)))
      (max reset (event-start e))))
  (for/fold ([local (if hold? (content-time a (asset-poster a)) 0)]) ([e (in-list events)]
              #:when (and (eq? (event-kind e) 'play) (eq? slot (car (event-target e)))
                          (= variant (event-variant e)) (>= (event-start e) reset)
                          (>= time (event-start e))))
    (+ (event-from e) (* (progress time (event-start e) (event-duration e))
                         (- (event-to e) (event-from e))))))
(define (property kind)
  (case kind [(reveal conceal) 'opacity] [(emphasize) 'scale] [(play) 'clock] [(replace) 'content]))
(define (span-overlap? a b)
  (define as (event-start a)) (define ae (+ as (event-duration a)))
  (define bs (event-start b)) (define be (+ bs (event-duration b)))
  (cond [(and (= as ae) (= bs be)) (= as bs)]
        [(= as ae) (and (<= bs as) (< as be))]
        [(= bs be) (and (<= as bs) (< bs ae))]
        [else (< (max as bs) (min ae be))]))
(define (events-conflict? a b)
  (and (paths-overlap? (event-target a) (event-target b)) (span-overlap? a b)
       (or (eq? (property (event-kind a)) (property (event-kind b)))
           (and (memq (event-kind a) '(play replace)) (memq (event-kind b) '(play replace))))))
(define (compile-slide-clip prepared original prepare-narration*)
  (define slots (prepared-slide-value-slots prepared))
  (define paths (slot-leaf-paths slots))
  (define initial (clip-value-initial original))
  (when (list? initial)
    (for ([selector (in-list initial)])
      (unless (ormap (lambda (p) (path-prefix? (selector-path selector) p)) paths)
        (slides-error 'unknown-selector (selector-path selector) "initial selector names no content"))))
  (define events '()) (define beats '()) (define time 0)
  (for ([b (in-list (clip-value-beats original))])
    (define narration (prepare-narration* (beat-value-narration b)))
    (define narration-end (if narration (+ (prepared-narration-start narration) (prepared-narration-duration narration)) 0))
    (define extent narration-end)
    ;; Sort by time; source order is never used to settle conflicting writes.
    (for ([a (in-list (sort (beat-value-actions b) < #:key action-value-at))])
      (define target (action-value-target a))
      (define name (car target))
      (define slot (findf (lambda (s) (eq? (prepared-slot-name s) name)) slots))
      (unless slot (slides-error 'unknown-selector target "action names an unknown slot"))
      (define targets (filter (lambda (p) (path-prefix? target p)) paths))
      (when (null? targets) (slides-error 'unknown-selector target "action selector names no content"))
      (define start (+ time (action-value-at a)))
      (define kind (action-value-kind a))
      (define variant (variant-at events name start))
      (define duration (action-value-duration a))
      (define from #f) (define to #f)
      (case kind
        [(reveal conceal)
         (set! from (for/hash ([path (in-list targets)]) (values path (visibility-at events initial path start))))
         (set! to (if (eq? kind 'reveal) 1 0))]
        [(emphasize) (set! from 1) (set! to (action-value-payload a))]
        [(replace)
         (set! from variant)
         (set! to (index-of (prepared-slot-source slot) (action-value-payload a) equal?))
         (unless to (slides-error 'unprepared-replacement target "replacement content was not prepared"))]
        [(play)
         (define leaves (list-ref (prepared-slot-variants slot) variant))
         (unless (= (length leaves) 1) (slides-error 'play-target target "play-content needs a single animated component"))
         (define asset (prepared-leaf-asset (car leaves)))
         (unless (> (asset-duration asset) 0) (slides-error 'not-animated target "selected content has no animation"))
         (define explicit-from (hash-ref (action-value-options a) 'from #f))
         (set! from (if explicit-from (content-time asset explicit-from)
                        (clock-at events name variant asset start (clip-value-hold? original))))
         (set! to (content-time asset (action-value-payload a)))
         (when (< to from) (slides-error 'backward-play target "backward destinations require an explicit reset via #:from"))
         (when (and duration (not (hash-ref (action-value-options a) 'retime #f))
                    (> (abs (- duration (- to from))) 1e-8))
           (slides-error 'retime-required target "a changed playback duration requires #:retime 'stretch"))
         (when (and duration (= duration 0) (> to from))
           (slides-error 'zero-play-duration target "advancing content needs positive playback time"))
         (set! duration (or duration (- to from)))])
      (define motion (prepared-slide-value-motion prepared))
      (define effect (if (and (eq? motion 'reduced) (memq kind '(reveal conceal))) 'instant (action-value-effect a)))
      (define next (event kind target start duration from to effect variant))
      (for ([old (in-list events)])
        (when (events-conflict? old next)
          (slides-error 'action-conflict (cons (beat-value-name b) target)
                        "overlapping actions write the same property or replace playing content")))
      (set! events (append events (list next)))
      (set! extent (max extent (+ (action-value-at a) duration))))
    (define required (+ extent (beat-value-tail b)))
    (define duration (or (beat-value-duration b) required))
    (unless (positive-number? duration) (slides-error 'beat-duration (list (beat-value-name b)) "resolved beat must have positive duration"))
    (when (> required (+ duration 1e-8))
      (slides-error 'beat-overrun (list (beat-value-name b))
                    "actions, narration, and tail hold exceed explicit beat duration"
                    (hash 'required required 'duration duration)))
    (set! beats (append beats (list (prepared-beat (beat-value-name b) time duration narration))))
    (set! time (+ time duration)))
  (define result (prepared-clip-value prepared events beats time initial (clip-value-poster original) (clip-value-hold? original)))
  (clip-time result (clip-value-poster original))
  result)
(define (clip-time clip selection)
  (define selected (or selection (prepared-clip-value-poster clip)))
  (define result
    (cond [(eq? selected 'end) (prepared-clip-value-duration clip)]
          [(eq? selected 'start) 0]
          [(nonnegative-number? selected) selected]
          [else
           (match selected
             [(list name (and boundary (or 'start 'end)))
              (define b (findf (lambda (b) (eq? name (prepared-beat-name b))) (prepared-clip-value-beats clip)))
              (unless b (slides-error 'unknown-beat (list name) "unknown beat boundary"))
              (+ (prepared-beat-start b) (if (eq? boundary 'end) (prepared-beat-duration b) 0))]
             [_ (slides-error 'invalid-time (list selected) "expected time, start/end, or (beat start/end)")])]))
  (unless (<= result (+ (prepared-clip-value-duration clip) 1e-8))
    (slides-error 'time-range (list result) "sample time exceeds clip duration"))
  (min result (prepared-clip-value-duration clip)))
