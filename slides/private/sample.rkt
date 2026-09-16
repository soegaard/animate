#lang racket/base
(require racket/list (only-in racket/math pi)
         "data.rkt" "check.rkt" "appearance.rkt" "schedule.rkt" "arrange.rkt"
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
    (for ([key (in-list (transition-value-keys (prepared-bridge-transition bridge)))])
      (for ([endpoint (in-list (list from to))] [side (in-list '(source destination))])
        (define leaves (key-leaves endpoint key))
        (when (null? leaves) (slides-error 'missing-continuity-key (list (prepared-bridge-from bridge) (prepared-bridge-to bridge) key side)
                                          "requested continuity key is absent"))
        (unless (ormap (lambda (l) (> (frame-leaf-opacity l) 0)) leaves)
          (slides-error 'invisible-match (list key side) "requested continuity key is invisible at the bridge endpoint")))))
  board)
(define (lerp a b p) (+ a (* p (- b a))))
(define (box-lerp a b p)
  (box-value (lerp (box-value-x a) (box-value-x b) p) (lerp (box-value-y a) (box-value-y b) p)
             (lerp (box-value-width a) (box-value-width b) p) (lerp (box-value-height a) (box-value-height b) p)))
(define (compatible? a b)
  (and (asset-identity (frame-leaf-asset a))
       (equal? (asset-identity (frame-leaf-asset a)) (asset-identity (frame-leaf-asset b)))
       (= (frame-leaf-time a) (frame-leaf-time b))
       (not (frame-leaf-clip a)) (not (frame-leaf-clip b))))
(define (bridge-frame board bridge t)
  (define-values (from to) (bridge-frames board bridge))
  (define transition (prepared-bridge-transition bridge))
  (define p (progress t (prepared-bridge-start bridge) (transition-value-duration transition)))
  (cond [(= p 0) from] [(= p 1) to]
        [else
         (define matched-from '()) (define matched-to '()) (define matched '())
         (for ([key (in-list (transition-value-keys transition))])
           (define aa (key-leaves from key)) (define bb (key-leaves to key))
           (when (= (length aa) (length bb))
             (define pairs
               (if (= (length aa) 1) (list (cons (car aa) (car bb)))
                   (for/list ([a (in-list aa)])
                     (cons a (findf (lambda (b) (equal? (cddr (frame-leaf-path a)) (cddr (frame-leaf-path b)))) bb)))))
             (when (andmap (lambda (pair) (and (cdr pair) (compatible? (car pair) (cdr pair)))) pairs)
               (for ([pair (in-list pairs)])
                 (define a (car pair)) (define b (cdr pair))
                 (set! matched-from (cons a matched-from)) (set! matched-to (cons b matched-to))
                 (set! matched
                       (cons (struct-copy frame-leaf b
                               [asset (frame-leaf-asset a)]
                               [box (box-lerp (frame-leaf-box a) (frame-leaf-box b) p)]
                               [opacity (lerp (frame-leaf-opacity a) (frame-leaf-opacity b) p)]
                               [scale (lerp (frame-leaf-scale a) (frame-leaf-scale b) p)]) matched))))))
         (define (fade unmatched removed weight)
           (for/list ([l (in-list unmatched)] #:unless (memq l removed))
             (struct-copy frame-leaf l [opacity (* weight (frame-leaf-opacity l))])))
         (frame-value (frame-value-format from)
                      (rgba-color-lerp (frame-value-background from) (frame-value-background to) p)
                      (append (fade (frame-value-leaves from) matched-from (- 1 p))
                              (fade (frame-value-leaves to) matched-to p) (reverse matched))
                      (for/fold ([h (frame-value-slots from)]) ([(k v) (in-hash (frame-value-slots to))]) (hash-set h k v))
                      (frame-value-safe-box to)
                      ;; Chrome uses the same explicit bridge alpha in both
                      ;; adapters, independently of content clocks.
                      (if (equal? (frame-value-decorations from) (frame-value-decorations to))
                          (frame-value-decorations from)
                          (append
                           (map (lambda (d) (list (car d) (cadr d) (- 1 p))) (frame-value-decorations from))
                           (map (lambda (d) (list (car d) (cadr d) p)) (frame-value-decorations to))))) ]))
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
