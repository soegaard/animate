#lang racket/base
(require racket/list (only-in racket/math pi)
         "data.rkt" "check.rkt" "appearance.rkt" "schedule.rkt" "arrange.rkt" "transition.rkt" "semantic-plan.rkt"
         "../../colors.rkt")
(provide sample-slide sample-storyboard validate-bridges storyboard-time prefix-frame canonical-scene-time)
(define (sample-slide source [selection #f])
  (define clip (and (prepared-clip-value? source) source))
  (define slide (if clip (prepared-clip-value-slide clip) source))
  (define time (if clip (clip-time clip selection) 0))
  (when (and (not clip) selection (not (member selection '(start end 0))))
    (slides-error 'static-time '() "plain slides have no timeline; use a clip to sample a time"))
  (define events (if clip (prepared-clip-value-events clip) '()))
  (define leaves
    (append-map
     (lambda (slot)
       (append-map
        (lambda (va)
          (define variant (car va)) (define weight (cdr va))
          (for/list ([leaf (in-list (list-ref (prepared-slot-variants slot) variant))])
            (define path (prepared-leaf-path leaf))
            (define a (prepared-leaf-asset leaf))
            (define opacity (* weight (if clip (visibility-at events (prepared-clip-value-initial clip) path time) 1)))
            (define scale
              (if (eq? (prepared-slide-value-motion slide) 'reduced) 1
                  (for/fold ([scale 1]) ([e (in-list events)]
                              #:when (and (eq? (event-kind e) 'emphasize)
                                          (path-prefix? (event-target e) path)
                                          (<= (event-start e) time)
                                          (< time (+ (event-start e) (event-duration e)))))
                    (+ 1 (* (- (event-to e) 1) (sin (* pi (progress time (event-start e) (event-duration e)))))))))
            (define local (if clip (clock-at events (prepared-slot-name slot) variant a time (prepared-clip-value-hold? clip))
                              (content-time a (asset-poster a))))
            (frame-leaf path (prepared-leaf-box leaf) a local opacity scale
                        (prepared-leaf-key leaf) (prepared-leaf-clip leaf))))
        (if clip (active-variants events (prepared-slot-name slot) time) (list (cons 0 1)))))
     (prepared-slide-value-slots slide)))
  (define theme (prepared-slide-value-theme slide))
  (define slots (for/hash ([s (in-list (prepared-slide-value-slots slide))])
                  (values (list (prepared-slot-name s)) (prepared-slot-box s))))
  (define rules
    (for/list ([entry (in-list '((title title-rule? below) (footer footer-rule? above)))]
               #:when (and (hash-ref (theme-value-decorations theme) (cadr entry) #f)
                           (hash-has-key? slots (list (car entry)))))
      (define b (hash-ref slots (list (car entry))))
      (list (box-value (box-value-x b)
                       (if (eq? (caddr entry) 'below) (+ (box-value-y b) (box-value-height b) 0.12)
                           (- (box-value-y b) 0.12))
                       (box-value-width b) 0.015)
            (resolve-color (role-color 'accent) (theme-value-colors theme)))))
  (frame-value (prepared-slide-value-format slide)
               (resolve-color theme-background (theme-value-colors theme))
               leaves slots
               (slide-safe-box (prepared-slide-value-source slide) (prepared-slide-value-format slide)
                               theme (prepared-slide-value-subtitle-height slide)) rules))
(define (prefix-frame f id)
  (struct-copy frame-value f
    [leaves (for/list ([l (in-list (frame-value-leaves f))])
              (struct-copy frame-leaf l [path (cons id (frame-leaf-path l))]))]
    [slots (for/hash ([(k v) (in-hash (frame-value-slots f))]) (values (cons id k) v))]))
(define scene-time-epsilon 1e-9)
(define (snap-scene-time time boundaries)
  ;; `value-to` reaches an authored global time through floating interpolation.
  ;; At a discontinuous cut that can yield 2.9999999999999996 for an authored
  ;; boundary at 3.  Snap only the Scene adapter's clock, never ordinary direct
  ;; `slide->pict #:at` sampling, so public near-boundary queries retain their
  ;; literal meaning.
  (or (for/first ([boundary (in-list boundaries)]
                  #:when (<= (abs (- time boundary)) scene-time-epsilon))
        boundary)
      time))
(define (clip-scene-boundaries clip [offset 0])
  (append
   (list offset (+ offset (prepared-clip-value-duration clip)))
   (append-map
    (lambda (b)
      (define start (+ offset (prepared-beat-start b)))
      (list start (+ start (prepared-beat-duration b))))
    (prepared-clip-value-beats clip))
   (append-map
    (lambda (e)
      (define start (+ offset (event-start e)))
      (list start (+ start (event-duration e))))
    (prepared-clip-value-events clip))))
(define (canonical-scene-time source storyboard? time)
  (define boundaries
    (cond
      [storyboard?
       (append
        (list 0 (prepared-storyboard-value-duration source))
        (append-map
         (lambda (shot)
           (clip-scene-boundaries (prepared-shot-clip shot) (prepared-shot-start shot)))
         (prepared-storyboard-value-shots source))
        (append-map
         (lambda (bridge)
           (define start (prepared-bridge-start bridge))
           (list start
                 (+ start
                    (transition-value-duration
                     (prepared-bridge-transition bridge)))))
         (prepared-storyboard-value-bridges source)))]
      [(prepared-clip-value? source)
       (clip-scene-boundaries source)]
      [else (list 0)]))
  (snap-scene-time time boundaries))
(define (find-shot b id)
  (or (findf (lambda (s) (eq? id (prepared-shot-id s))) (prepared-storyboard-value-shots b))
      (slides-error 'unknown-shot (list id) "unknown prepared shot")))
(define (bridge-frames board bridge)
  (define from (find-shot board (prepared-bridge-from bridge)))
  (define to (find-shot board (prepared-bridge-to bridge)))
  (values (prefix-frame (sample-slide (prepared-shot-clip from) 'end) (prepared-shot-id from))
          (prefix-frame (sample-slide (prepared-shot-clip to) 'start) (prepared-shot-id to))))
(define (key-leaves frame key)
  (filter (lambda (l) (eq? key (frame-leaf-key l))) (frame-value-leaves frame)))
(define (validate-bridges board)
  (for ([bridge (in-list (prepared-storyboard-value-bridges board))])
    (define-values (from to) (bridge-frames board bridge))
    (define tr (prepared-bridge-transition bridge))
    (when (memq (transition-value-effect tr) '(push wipe cover uncover))
      (for ([f (in-list (list from to))])
        (unless (= (rgba-color-alpha (frame-value-background f)) 1)
          (slides-error 'transition-background '()
                        "directional transitions require opaque slide backgrounds"))))
    (when (eq? (transition-value-effect tr) 'fade-through)
      (define destination (find-shot board (prepared-bridge-to bridge)))
      (define theme (prepared-slide-value-theme
                     (prepared-clip-value-slide (prepared-shot-clip destination))))
      (define color (resolve-color (transition-value-color tr) (theme-value-colors theme)))
      (unless (= (rgba-color-alpha color) 1)
        (slides-error 'transition-color '() "fade-through requires an opaque midpoint color")))
    (for ([key (in-list (transition-value-keys (prepared-bridge-transition bridge)))])
      (for ([endpoint (in-list (list from to))] [side (in-list '(source destination))])
        (define leaves (key-leaves endpoint key))
        (when (null? leaves) (slides-error 'missing-continuity-key (list (prepared-bridge-from bridge) (prepared-bridge-to bridge) key side)
                                          "requested continuity key is absent"))
        (unless (ormap (lambda (l) (> (frame-leaf-opacity l) 0)) leaves)
          (slides-error 'invisible-match (list key side) "requested continuity key is invisible at the bridge endpoint")))))
  (define planned
    (for/list ([bridge (in-list (prepared-storyboard-value-bridges board))])
      (define tr (prepared-bridge-transition bridge))
      (define-values (from to) (bridge-frames board bridge))
      (struct-copy prepared-bridge bridge
        [plan (if (eq? (transition-value-effect tr) 'match)
                  (for/list ([key (in-list (transition-value-keys tr))])
                    (compile-match-plan key (key-leaves from key) (key-leaves to key)
                                        (transition-value-depth tr)))
                  '())])))
  (struct-copy prepared-storyboard-value board [bridges planned]))
(define (matched-bridge-frame board bridge p)
  (define-values (from to) (bridge-frames board bridge))
  (cond
    [(= p 0) from] [(= p 1) to]
    [else
     (define plans (prepared-bridge-plan bridge))
     (unless plans
       (slides-error 'unprepared-match '() "semantic matching must be planned before sampling"))
     (define keys (map match-plan-key plans))
     (define base (blend-frames from to p))
     (struct-copy frame-value base
       [leaves
        (append
         (filter (lambda (l) (not (memq (frame-leaf-key l) keys)))
                 (frame-value-leaves base))
         (append-map (lambda (plan) (sample-match-plan plan p)) plans))])]))

(define (bridge-frame board bridge time)
  (define tr (prepared-bridge-transition bridge))
  (define p (transition-progress (transition-value-easing tr)
               (progress time (prepared-bridge-start bridge) (transition-value-duration tr))))
  (define-values (from to) (bridge-frames board bridge))
  ;; A reduced-motion storyboard keeps bridge durations, speech alignment, and
  ;; all endpoint states. Only spatial motion is replaced with a crossfade.
  (define reduced? (eq? (storyboard-value-motion (prepared-storyboard-value-source board)) 'reduced))
  (define effect (if (and reduced? (memq (transition-value-effect tr)
                                        '(match push wipe cover uncover zoom)))
                     'crossfade (transition-value-effect tr)))
  (cond
    [(= p 0) from]
    [(= p 1) to]
    [else
     (case effect
       [(match) (matched-bridge-frame board bridge p)]
       [(crossfade) (blend-frames from to p)]
       [(push wipe cover uncover)
        (directional-bridge from to effect (transition-value-direction tr) p)]
       [(zoom)
        (define scale (transition-value-scale tr))
        (blend-frames (zoom-frame from (+ 1 (* p (- (/ 1 scale) 1))))
                      (zoom-frame to (+ scale (* p (- 1 scale)))) p)]
       [(fade-through)
        ;; Semantic transition colors resolve against the destination theme.
        (define destination (find-shot board (prepared-bridge-to bridge)))
        (define theme (prepared-slide-value-theme
                       (prepared-clip-value-slide (prepared-shot-clip destination))))
        (fade-through-frame from to
          (resolve-color (transition-value-color tr) (theme-value-colors theme)) p)]
       [else (slides-error 'transition-effect '() "unknown prepared transition")])]))
(define (storyboard-time b selected)
  (define t (case selected [(end) (prepared-storyboard-value-duration b)] [(start) 0] [else selected]))
  (unless (and (nonnegative-number? t) (<= t (+ 1e-8 (prepared-storyboard-value-duration b))))
    (slides-error 'time-range (list selected) "storyboard time is outside its duration"))
  (min t (prepared-storyboard-value-duration b)))
(define (sample-storyboard b selected)
  (define t (storyboard-time b selected))
  (define bridge
    (findf (lambda (bridge)
             (and (<= (prepared-bridge-start bridge) t)
                  (< t (+ (prepared-bridge-start bridge) (transition-value-duration (prepared-bridge-transition bridge))))))
           (prepared-storyboard-value-bridges b)))
  (cond [bridge
         (define frame (bridge-frame b bridge t))
         ;; Use the same occurrence/slot draw order as native Scene roots.
         (define order
           (for*/list ([shot (in-list (prepared-storyboard-value-shots b))]
                       [slot (in-list (prepared-slide-value-slots
                                       (prepared-clip-value-slide (prepared-shot-clip shot))))])
             (list (prepared-shot-id shot) (prepared-slot-name slot))))
         (struct-copy frame-value frame
           [leaves (sort (frame-value-leaves frame) <
                         #:key (lambda (leaf) (index-of order (take (frame-leaf-path leaf) 2) equal?)))])]
        [else
         (define shots (prepared-storyboard-value-shots b))
         (define shot
           (or (findf (lambda (s) (and (<= (prepared-shot-start s) t)
                                       (< t (+ (prepared-shot-start s) (prepared-clip-value-duration (prepared-shot-clip s)))))) shots)
               (last shots)))
         (prefix-frame (sample-slide (prepared-shot-clip shot) (- t (prepared-shot-start shot))) (prepared-shot-id shot))]))
