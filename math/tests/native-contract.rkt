#lang racket/base

;;;
;;; Native Adapter Contract Tests
;;;
;; Uses an explicit synthetic API model to test native calls and phase compilation. This
;; is not animate and is not a renderer.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list count last remove-duplicates)
  racket/match
  "check.rkt"
  "../main.rkt"
  "../private/native.rkt"
  "../private/typeset.rkt"
  (prefix-in adapter: "../private/animate-adapter.rkt")
  (prefix-in lc: "../examples/linear-concrete.rkt")
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qc: "../examples/quadratic-concrete.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;; Exports
(provide run-native-contract-tests)

;;;
;;; Data Representation
;;;
(struct point (x y)
  #:transparent)

;; point is an immutable record. Its fields have the following roles.
;;  - x  finite-real?  x coordinate in synthetic world units.
;;  - y  finite-real?  y coordinate in synthetic world units.
(struct camera (width height world-width background)
  #:transparent)

;; camera is an immutable record. Its fields have the following roles.
;;  - width  exact-positive-integer?  synthetic output width in pixels.
;;  - height  exact-positive-integer?  synthetic output height in pixels.
;;  - world-width  positive-real?  visible horizontal world extent.
;;  - background  string?  captured background description.
(struct visual (kind id position opacity width height content)
  #:transparent)

;; visual is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  synthetic Visual family.
;;  - id  symbol?  stable scene identity.
;;  - position  point?  reference position in world coordinates.
;;  - opacity  real?  semantic opacity in [0, 1].
;;  - width  positive-real?  synthetic width in world units.
;;  - height  positive-real?  synthetic height in world units.
;;  - content  any/c  synthetic text or source reference; no rendered pixels.
(struct request (kind id value)
  #:transparent)

;; request is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  tested animation component.
;;  - id  symbol?  target identity.
;;  - value  any/c  exact requested component endpoint.
(struct clip (start duration before after requests)
  #:transparent)

;; clip is an immutable record. Its fields have the following roles.
;;  - start  nonnegative-real?  absolute start time in seconds.
;;  - duration  positive-real?  clip length in seconds.
;;  - before  immutable-hash?  starting Visual snapshot.
;;  - after  immutable-hash?  exact completed Visual snapshot.
;;  - requests  list?  component requests in significant application order.
(struct scene (visuals data camera duration clips)
  #:transparent)

;; scene is an immutable record. Its fields have the following roles.
;;  - visuals  immutable-hash?  synthetic identity lookup; not a renderer.
;;  - data  immutable-hash?  named scalar checkpoint values.
;;  - camera  camera?  captured output camera.
;;  - duration  nonnegative-real?  total length in seconds.
;;  - clips  (listof clip?)  clips in chronological order.
; make-camera : [#:width any/c] [#:height any/c] [#:world-width any/c] [#:background
;   any/c] -> camera?
;;   Builds a renderer-free camera descriptor for native contract tests.
(define (make-camera
          #:width [w 1280]
          #:height [h 720]
          #:world-width [ww 14]
          #:background [bg "white"])
  (camera w h ww bg))

; make-scene : [#:camera any/c] -> scene?
;;   Creates an empty immutable scene for the native API contract model.
(define (make-scene #:camera [c (make-camera)])
  (scene (hash) (hash) c 0 '()))

; svg-image : any/c #:id symbol? #:center any/c [#:opacity (real-in 0 1)] #:width any/c
;   #:height any/c -> visual?
;;   Creates a synthetic Visual descriptor without loading a renderer.
(define (svg-image source
          #:id id
          #:center center
          #:opacity [opacity 1]
          #:width width
          #:height height)
  (visual 'svg id center opacity width height source))

; plain-text : any/c #:id symbol? #:center any/c #:font-size any/c #:color any/c ->
;   visual?
;;   Creates a synthetic Visual descriptor without loading a renderer.
(define (plain-text text #:id id #:center center #:font-size size #:color color)
  (visual 'text id center 1 (* (string-length text) size .5) size (list text color)))

; scene-add : any/c any/c ... -> scene?
;;   Applies the tested native API contract to an immutable synthetic scene.
(define (scene-add s . vs)
  (struct-copy scene s
    [visuals
     (for/fold ([h (scene-visuals s)]) ([v (in-list vs)])
       (when (hash-has-key? h (visual-id v))
         (error 'scene-add "duplicate identity ~s" (visual-id v)))
       (hash-set h (visual-id v) v))]))

; scene-remove : any/c any/c ... -> scene?
;;   Applies the tested native API contract to an immutable synthetic scene.
(define (scene-remove s . ids)
  (struct-copy scene s
    [visuals
     (for/fold ([h (scene-visuals s)]) ([id (in-list ids)])
       (unless (hash-has-key? h id) (error 'scene-remove "unknown identity ~s" id))
       (hash-remove h id))]))

; scene-set-value : any/c symbol? any/c -> scene?
;;   Applies the tested native API contract to an immutable synthetic scene.
(define (scene-set-value s id data)
  (unless (real? data)
    (error 'scene-set-value "expected interpolable scalar, not metadata"))
  (struct-copy scene s [data (hash-set (scene-data s) id data)]))

; scene-play : any/c #:duration math-datum? any/c ... -> scene?
;;   Applies the tested native API contract to an immutable synthetic scene.
(define (scene-play s #:duration d . requests)
  (unless (> d 0) (error 'scene-play "positive duration required"))
  (define keys (map (lambda (r) (cons (request-id r) (request-kind r))) requests))
  (unless (= (length keys) (length (remove-duplicates keys)))
    (error 'scene-play "duplicate component requests"))
  (define result
    (for/fold ([h (scene-visuals s)]) ([r (in-list requests)])
      (define v
        (hash-ref h
          (request-id r)
          (lambda () (error 'scene-play "unknown target ~s" (request-id r)))))
      (hash-set h
        (request-id r)
        (case (request-kind r)
          [(move) (struct-copy visual v [position (request-value r)])]
          [(fade)
           (unless (<= 0 (request-value r) 1) (error 'fade-to "opacity"))
           (struct-copy visual v [opacity (request-value r)])]
          [else (error 'scene-play "unsupported request")]))))
  (scene result
    (scene-data s)
    (scene-camera s)
    (+ (scene-duration s) d)
    (append
      (scene-clips s)
      (list (clip (scene-duration s) d (scene-visuals s) result requests)))))

; scene-wait : any/c math-datum? -> scene?
;;   Applies the tested native API contract to an immutable synthetic scene.
(define (scene-wait s d)
  (scene-play s #:duration d))

; functions : immutable-hash?
;;   Maps supported native names to explicit contract-model implementations.
(define functions
  (hash 'make-camera make-camera 'camera-width camera-width 'camera-height camera-height 'camera-world-width camera-world-width 'make-scene make-scene 'scene-add scene-add 'scene-remove scene-remove 'scene-play scene-play 'scene-wait scene-wait 'scene-set-value scene-set-value 'vec2 point 'svg-image svg-image 'plain-text plain-text 'move-to
    (lambda (id v) (request 'move id v))
    'fade-to
    (lambda (id v) (request 'fade id v))
    'scene-sample
    (lambda (scn time) (scene-visuals scn))
    'scene-camera-at
    (lambda (scn time) (scene-camera scn))
    'default-pict-renderers
    '(contract-default-renderer)
    'scene-state->pict
    (lambda (state #:camera camera #:renderers renderers)
      (list 'contract-pict state camera renderers))
    'group
    (lambda (vs #:id id) (list 'group id vs))))

; loader : any/c symbol? -> any/c
;;   Resolves only explicitly modeled native bindings and rejects all other requests.
(define (loader scope name)
  (unless (eq? scope 'animate) (error 'contract-model "unexpected scope ~s" scope))
  (hash-ref functions name
    (lambda () (error 'contract-model "unexpected native function ~s" name))))

; preparations : exact-nonnegative-integer?
;;   Counts synthetic typesetter calls to detect effect-boundary violations.
(define preparations
  0)

; synthetic-typesetter : math? any/c symbol? string? path-string? -> prepared-layout?
;;   Builds synthetic ordered token geometry solely for adapter contract tests.
(define (synthetic-typesetter state size multiplication foreground directory)
  (set! preparations (add1 preparations))
  (define src (format-math-source state #:multiplication multiplication))
  (define spans
    (filter
      (lambda (s) (not (eq? (math-source-span-role s) 'expression)))
      (math-source-spans src)))
  (define tokens
    (for/list ([span (in-list spans)] [i (in-naturals)])
      (define content
        (substring
          (math-source-text src)
          (math-source-span-start span)
          (math-source-span-end span)))
      (prepared-token
        (math-source-span-path span)
        (math-source-span-role span)
        content
        "synthetic-test-asset.svg"
        (* .15 (math-source-span-start span))
        0
        (* .12 (max 1 (string-length content)))
        .4
        (string->symbol (format "token~a" i)))))
  (prepared-layout state tokens src '("Synthetic typography: contract test only.")))

; clip-for-time : any/c any/c -> (or/c clip? #f)
;;   Finds the half-open clip that owns a contract-test sample time.
(define (clip-for-time s t)
  (findf
    (lambda (c) (and (<= (clip-start c) t) (< t (+ (clip-start c) (clip-duration c)))))
    (scene-clips s)))

; run-native-contract-tests : -> void?
;;   Runs the named regression groups and records failures in the test harness.
(define (run-native-contract-tests)
  (test-group
    "native adapter contract model: four examples"
    (lambda ()
      (parameterize ([current-native-loader loader]
                      [current-math-typesetter synthetic-typesetter])
        (for ([plan (in-list (list lc:plan lg:plan qc:plan qg:plan))])
          (define before preparations)
          (define prepared (adapter:prepare-math-plan! plan))
          (check-true (> preparations before) 'preparation-done)
          (define count preparations)
          (define s (adapter:math-plan->scene! prepared))
          (check-equal preparations count 'no-typesetting-during-scene-compilation)
          (check-close (scene-duration s) (plan-duration plan) 1e-7 'duration-agreement)
          (define last-segment (last (presentation-plan-segments plan)))
          (define final (after (plan-segment-derivation last-segment)))
          (define checkpoint-index (hash-ref (scene-data s) 'math-lesson.checkpoint))
          (define checkpoints (plan-checkpoints plan))
          (check-equal checkpoint-index (sub1 (vector-length checkpoints)))
          (check-equal
            (math-datum (math-checkpoint-state (vector-ref checkpoints checkpoint-index)))
            (math-datum final))
          (check-true
            (andmap (lambda (v) (= (visual-opacity v) 1)) (hash-values (scene-visuals s)))
            'exact-visible-endpoint)
          (check-true (positive? (hash-count (scene-visuals s))))
          (for ([c (in-list (scene-clips s))])
            (check-true (> (clip-duration c) 0) 'positive-native-clip))
          (check-equal preparations count 'sampling-independent-of-typesetter)))))
  (test-group
    "native adapter contract model: held cancellation and layout"
    (lambda ()
      (parameterize ([current-native-loader loader]
                      [current-math-typesetter synthetic-typesetter])
        (define s (adapter:math-plan->scene! lc:plan))
        (define cancellation
          (findf
            (lambda (p)
              (and
                (equal? (scheduled-phase-step p) '(isolate-term cancel-five))
                (eq? (scheduled-phase-kind p) 'retire-cancelled)))
            (plan-schedule lc:plan)))
        (define c (clip-for-time s (+ (scheduled-phase-start cancellation) .01)))
        (check-true c)
        (check-true (pair? (clip-requests c)))
        (check-true
          (andmap (lambda (r) (eq? (request-kind r) 'fade)) (clip-requests c))
          'no-moving-during-cancel)
        (for ([(id v) (in-hash (clip-before c))])
          (check-equal
            (visual-position (hash-ref (clip-after c) id))
            (visual-position v)
            'position-held))
        (define hold-phase
          (findf
            (lambda (p)
              (and
                (equal? (scheduled-phase-step p) '(isolate-term cancel-five))
                (eq? (scheduled-phase-kind p) 'hold)))
            (plan-schedule lc:plan)))
        (check-equal
          (clip-requests (clip-for-time s (+ (scheduled-phase-start hold-phase) .01)))
          '()
          'pause-is-native-wait)
        (check-raises
          (lambda ()
            (adapter:math-plan->scene! (choreograph lc:plan [(isolate-term cancel-five) (hold 1)])))
          #rx"retire|position")
        (define plain
          (present lc:solution
            #:style (math-presentation #:history 'replace #:reflow 'simultaneous)))
        (check-close
          (scene-duration (adapter:math-plan->scene! plain))
          (plan-duration plain))
        (define one-case (present qg:solution #:case '(quadratic one-real-root)))
        (check-close
          (scene-duration (adapter:math-plan->scene! one-case))
          (plan-duration one-case))
        (check-true (pair? (adapter:math->visual! lc:problem)))
        (define prepared (adapter:prepare-math-plan! lc:plan))
        (define dark-prepared (adapter:prepare-math-plan! lc:plan #:theme 'dark))
        (check-equal
          (car (adapter:math-plan->pict! dark-prepared 0))
          'contract-pict
          'captured-dark-theme)
        (define mock-pict
          (adapter:math-plan->pict! prepared 0 #:renderers '(custom-renderer)))
        (check-equal (car mock-pict) 'contract-pict 'keyword-camera-contract)
        (check-equal (cadddr mock-pict) '(custom-renderer) 'renderer-propagation)
        (check-equal
          (cadddr (adapter:math-plan->pict! prepared 0))
          '(contract-default-renderer)
          'default-renderer-propagation)))))

;; A deliberately named test-only boundary for semantic transition regression tests.
(module+ support
  (provide loader synthetic-typesetter clip-for-time
           (struct-out point) (struct-out visual) (struct-out request)
           (struct-out clip) (struct-out scene)))
