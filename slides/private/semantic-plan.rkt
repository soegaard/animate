#lang racket/base

;; Correspondences are planned exactly once from prepared endpoints. The
;; renderer sees ordinary assets and geometry, never guessed mathematical ink.
(require racket/list "data.rkt" "check.rkt")
(provide compile-match-plan sample-match-plan match-plan->datum match-pair-box)

(define (meta leaf name [fallback #f])
  (hash-ref (asset-metadata (frame-leaf-asset leaf)) name fallback))
(define (visible leaves)
  (filter (lambda (leaf) (> (frame-leaf-opacity leaf) 0)) leaves))
(define (relative-id leaf) (cddr (frame-leaf-path leaf)))
(define (identity-compatible? a b)
  (and (asset-identity (frame-leaf-asset a))
       (equal? (asset-identity (frame-leaf-asset a)) (asset-identity (frame-leaf-asset b)))
       (= (frame-leaf-time a) (frame-leaf-time b))
       (not (frame-leaf-clip a)) (not (frame-leaf-clip b))))
(define (domain-reason a b)
  (cond
    [(not (and (meta a 'state-base) (meta b 'state-base))) 'not-two-domain-states]
    [(or (frame-leaf-clip a) (frame-leaf-clip b)) 'clipped-domain-state]
    [(not (equal? (meta a 'state-origin) (meta b 'state-origin))) 'different-domain-origin]
    [(> (meta a 'state-time) (meta b 'state-time)) 'backward-domain-transition]
    [else #f]))
(define (make-pair a b semantic? named? strict?)
  (define domain? (and semantic? (or (meta a 'state-base) (meta b 'state-base))))
  (define reason (and domain? (domain-reason a b)))
  (cond
    [(and domain? (not reason))
     (match-pair a b 'replay (meta a 'state-base) (meta a 'state-time) (meta b 'state-time)
                 (hash-ref (asset-metadata (meta a 'state-base)) 'kind 'native))]
    [(identity-compatible? a b)
     (match-pair a b 'preserve #f #f #f 'prepared-asset-identity)]
    [(and semantic? named? (not domain?))
     ;; Explicit child identity permits a moving appearance crossfade, but
     ;; never implies glyph correspondence or mathematical equivalence.
     (match-pair a b 'replace #f #f #f 'explicit-child-identity)]
    [strict?
     (slides-error 'semantic-match-unavailable (list (frame-leaf-key a) (relative-id a))
                   "no witnessed semantic transition between these endpoints"
                   (or reason 'incompatible-prepared-assets))]
    [else #f]))
(define (compile-match-plan key source target depth)
  (define aa (visible source)) (define bb (visible target))
  (define recursive?
    (and (not (eq? depth 'slot)) (pair? aa) (pair? bb)
         (andmap (lambda (l) (and (meta l 'semantic-path) #t)) aa)
         (andmap (lambda (l) (and (meta l 'semantic-path) #t)) bb)))
  ;; Replacement alternatives must not leave two simultaneous identities at
  ;; an endpoint. Never resolve duplicates by hash order or proximity.
  (for ([leaves (in-list (list aa bb))])
    (define paths (map relative-id leaves))
    (unless (= (length paths) (length (remove-duplicates paths equal?)))
      (slides-error 'ambiguous-semantic-match (list key)
                    "multiple visible endpoint leaves claim the same relative identity")))
  (define strict? (eq? depth 'semantic))
  (define candidates
    (cond
      [recursive?
       (filter values
        (for/list ([b (in-list bb)])
          (define a (findf (lambda (a) (equal? (meta a 'semantic-path) (meta b 'semantic-path))) aa))
          (and a (make-pair a b #t #t strict?))))]
      [(and (= (length aa) 1) (= (length bb) 1))
       (filter values (list (make-pair (car aa) (car bb) (not (eq? depth 'slot)) #f strict?)))]
      [(= (length aa) (length bb))
       ;; Preserve the preexisting all-or-nothing keyed-bullet behavior.
       (define pairs
         (for/list ([b (in-list bb)])
           (define a (findf (lambda (a) (equal? (relative-id a) (relative-id b))) aa))
           (and a (make-pair a b #f #f #f))))
       (if (andmap values pairs) pairs '())]
      [else '()]))
  (when (and strict? (not recursive?) (null? candidates))
    (slides-error 'semantic-match-unavailable (list key)
                  "no unambiguous semantic correspondence; use semantic-group or content-state"))
  (define used-source (map match-pair-source candidates))
  (define used-target (map match-pair-target candidates))
  (match-plan key candidates
              (filter (lambda (l) (not (member l used-source equal?))) aa)
              (filter (lambda (l) (not (member l used-target equal?))) bb)
              (cond [recursive? 'named-children]
                    [(pair? candidates) 'matched]
                    [(and (= (length aa) 1) (= (length bb) 1)
                          (or (meta (car aa) 'state-base) (meta (car bb) 'state-base)))
                     (or (domain-reason (car aa) (car bb)) 'slot-depth)]
                    [else 'crossfade-fallback])))

(define (lerp a b p) (+ a (* p (- b a))))
(define (box-lerp a b p)
  (box-value (lerp (box-value-x a) (box-value-x b) p)
             (lerp (box-value-y a) (box-value-y b) p)
             (lerp (box-value-width a) (box-value-width b) p)
             (lerp (box-value-height a) (box-value-height b) p)))
(define (compose-box parent local)
  (box-value (+ (box-value-x parent) (* (box-value-width parent) (box-value-x local)))
             (+ (box-value-y parent) (* (box-value-height parent) (box-value-y local)))
             (* (box-value-width parent) (box-value-width local))
             (* (box-value-height parent) (box-value-height local))))
(define (match-pair-box pair p)
  (define a (match-pair-source pair)) (define b (match-pair-target pair))
  (define ca (meta a 'semantic-chain)) (define cb (meta b 'semantic-chain))
  (cond
    [(and ca cb (= (length ca) (length cb)))
     ;; Interpolate the outer placement, then compose each local transform.
     ;; Interpolating already-baked child world coordinates would double-count
     ;; or lose parent motion when the parent and child both change size.
     (for/fold ([box (box-lerp (car ca) (car cb) p)])
               ([a (in-list (cdr ca))] [b (in-list (cdr cb))])
       (compose-box box (box-lerp a b p)))]
    [else (box-lerp (frame-leaf-box a) (frame-leaf-box b) p)]))
(define (sample-pair pair p)
  (define a (match-pair-source pair)) (define b (match-pair-target pair))
  (define box (match-pair-box pair p))
  (define alpha (lerp (frame-leaf-opacity a) (frame-leaf-opacity b) p))
  (define scale (lerp (frame-leaf-scale a) (frame-leaf-scale b) p))
  (define (placed template asset time weight)
    (struct-copy frame-leaf template [asset asset] [time time] [box box]
                 [opacity (* alpha weight)] [scale scale]))
  (case (match-pair-mode pair)
    [(replay)
     (list (placed b (match-pair-replay pair)
                   (lerp (match-pair-from-time pair) (match-pair-to-time pair) p) 1))]
    [(preserve) (list (placed b (frame-leaf-asset a) (frame-leaf-time a) 1))]
    [(replace)
     (list (placed b (frame-leaf-asset a) (frame-leaf-time a) (- 1 p))
           (placed b (frame-leaf-asset b) (frame-leaf-time b) p))]))
(define (sample-match-plan plan p)
  (append
   (for/list ([l (in-list (match-plan-outgoing plan))])
     (struct-copy frame-leaf l [opacity (* (- 1 p) (frame-leaf-opacity l))]))
   (for/list ([l (in-list (match-plan-incoming plan))])
     (struct-copy frame-leaf l [opacity (* p (frame-leaf-opacity l))]))
   (append-map (lambda (pair) (sample-pair pair p)) (match-plan-pairs plan))))
(define (match-plan->datum plan)
  (hash 'key (match-plan-key plan) 'reason (match-plan-reason plan)
        'pairs
        (for/list ([p (in-list (match-plan-pairs plan))])
          (hash 'from (frame-leaf-path (match-pair-source p))
                'to (frame-leaf-path (match-pair-target p))
                'mode (match-pair-mode p) 'evidence (match-pair-reason p)
                'content-start (match-pair-from-time p)
                'content-end (match-pair-to-time p)))
        'outgoing (map frame-leaf-path (match-plan-outgoing plan))
        'incoming (map frame-leaf-path (match-plan-incoming plan))))
