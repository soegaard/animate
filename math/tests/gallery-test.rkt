#lang racket/base

;;;
;;; Mathematical Gallery Regression Tests
;;;
;; Tests the pure catalogue and math, native adapter contracts, and portable file
;; handoff. The synthetic native model is never presented as actual rasterization.

;;;
;;; Imports and Exports
;;;
(require racket/list
         (only-in racket/file make-temporary-file delete-directory/files file->bytes)
         (only-in racket/port call-with-output-string)
         "check.rkt" "gallery-support.rkt"
         "../main.rkt" "../private/native.rkt" "../private/typeset.rkt"
         "../private/prepare.rkt" "../private/prepared-plan-codec.rkt"
         "../examples/gallery/model.rkt" "../examples/gallery/catalogue.rkt"
         "../examples/gallery/common.rkt" "../examples/gallery/render.rkt"
         "../examples/gallery/review-model.rkt" "../examples/gallery/artifacts.rkt"
         "../examples/gallery/source.rkt" "../examples/gallery/project.rkt")
(provide run-gallery-tests)

; first-plan : symbol? -> presentation-plan?
;;   Selects the main view of one named demonstration for focused invariant checks.
(define (first-plan name)
  (gallery-view-plan (car (gallery-plate-views (car (select-gallery-plates #:plates (list name)))))))

; first-derivation : symbol? -> derivation?
;;   Selects the first mathematical segment without altering its context or provenance.
(define (first-derivation name)
  (plan-segment-derivation (car (presentation-plan-segments (first-plan name)))))

; main-endpoints : immutable-hash?
;;   States the authored expected final expressions independently of the catalogue code.
(define main-endpoints
  (hash 'held-arithmetic '(= (- (+ (* 3 x) 5) 5) (- 17 5))
        'both-sides '(= (- (+ (* 3 x) 5) 5) (- 17 5))
        'additive-cancellation '(+ (expt x 2) (* 6 x))
        'factor-cancellation 'x 'focused-evaluation 4
        'signed-reorder '(+ (- b) (sqrt Δ)) 'occurrence-selection '(+ x 2 x)
        'structural-selection '(= x (/ 6 3)) 'distribution '(+ (* a b) (* a c))
        'checked-replacement '(expt (+ x 3) 2) 'domain-restriction 1
        'negative-inequality '(> x -3)
        'zero-product '(or (= (- x 1) 0) (= (+ x 2) 0))
        'square-roots '(or (= (+ x 3) 2) (= (+ x 3) -2))
        'candidate-check '(= 17 17) 'named-moves '(= (* 3 x) 12)
        'nested-moves '(= x 4) 'explanatory-inset '(= (expt (+ x 3) 2) 4)))

; expect-no-preparation : any/c ... -> none/c
;;   Makes an accidental worker preparation/typesetter invocation a hard test failure.
(define (expect-no-preparation . arguments)
  (error 'gallery-test "worker must not prepare or typeset"))

; run-gallery-tests : -> void?
;;   Runs catalogue, endpoint, composition, selection, and real-file codec regressions.
(define (run-gallery-tests)
  (test-group "gallery: catalogue and selection are pure and deterministic"
    (lambda ()
      (check-equal (length gallery-plates) 25 'plate-count)
      (check-equal (length (gallery-entries gallery-plates)) 31 'replay-count)
      (check-equal (map car gallery-chapters) '(held selection conditions moves presentation))
      (check-equal (map (lambda (chapter) (length (select-gallery-plates #:chapter (car chapter))))
                       gallery-chapters) '(6 4 7 4 4))
      (check-equal (map gallery-plate-id (select-gallery-plates #:plates '(history both-sides)))
                   '(both-sides history) 'canonical-order)
      (check-raises (lambda () (select-gallery-plates #:plates '(missing))) #rx"unknown plate")
      (check-raises (lambda () (select-gallery-plates #:plates '(history history))) #rx"unique")
      (check-raises (lambda () (select-gallery-plates #:plates '())) #rx"nonempty")
      (check-raises (lambda () (select-gallery-plates #:chapter 'bad)) #rx"unknown chapter")
      (check-raises (lambda () (select-gallery-plates #:chapter 'held #:plates '(history))) #rx"not in")
      (check-raises (lambda () (make-gallery-view 'bad/name "" (first-plan 'history) #:caption "x")) #rx"safe")
      (check-raises (lambda () (make-gallery-view 'fine "line\nbreak" (first-plan 'history) #:caption "x")) #rx"single-line")
      (check-equal (gallery-duration '()) 0)
      (check-true (exact? (gallery-duration gallery-plates)))))
  (test-group "gallery: mathematical endpoints, guards, and provenance"
    (lambda ()
      (for ([(name expected) (in-hash main-endpoints)])
        (check-equal (math-datum (derivation-final (first-derivation name))) expected name))
      (for* ([plate (in-list gallery-plates)] [view (in-list (gallery-plate-views plate))]
              [segment (in-list (presentation-plan-segments (gallery-view-plan view)))])
        (check-equal (verification-status (derivation-verification (plan-segment-derivation segment)))
                     'established (list 'verified (gallery-plate-id plate) (gallery-view-id view))))
      (check-equal (length (derivation-steps (first-derivation 'held-arithmetic))) 0)
      (define d (first-derivation 'domain-restriction))
      (check-true (member '(not (= x 0)) (math-context-restrictions (math-context-of (derivation-final d)))))
      (check-equal (rewrite-step-relation (car (derivation-steps (first-derivation 'occurrence-selection))))
                   'specialization)
      (check-true (ormap (lambda (relation) (eq? (trace-relation-kind relation) 'copy))
                         (rewrite-step-trace (car (derivation-steps (first-derivation 'distribution))))))
      (check-equal (rewrite-step-relation (car (derivation-steps (first-derivation 'implication)))) 'implication)
      (define bad-check (cadr (gallery-plate-views (car (select-gallery-plates #:plates '(implication))))))
      (check-equal (verification-status (plan-segment-verdict
                    (car (presentation-plan-segments (gallery-view-plan bad-check))))) 'refuted)
      (for ([name '(grouping history)])
        (for ([view (gallery-plate-views (car (select-gallery-plates #:plates (list name))))])
          (check-true (eq? gallery-history-solution
                           (presentation-plan-source (gallery-view-plan view))))))
      (define timing (gallery-plate-views (car (select-gallery-plates #:plates '(cancellation-timing)))))
      (check-true (eq? (presentation-plan-source (gallery-view-plan (car timing)))
                       (presentation-plan-source (gallery-view-plan (cadr timing)))))
      (check-equal (- (plan-duration (gallery-view-plan (cadr timing)))
                     (plan-duration (gallery-view-plan (car timing)))) 1)
      (check-equal (map (lambda (s) (math-datum (derivation-final (plan-segment-derivation s))))
                       (presentation-plan-segments (first-plan 'parameter-cases)))
                   '((= x (/ b a)) #t #f))
      (check-true (plan-segment-shared? (car (presentation-plan-segments (first-plan 'shared-prefix)))))))
  (test-group "gallery: review addresses and global times cover every replay"
    (lambda ()
      (define entries (gallery-entries gallery-plates))
      (define points (gallery-review-points entries))
      (for ([entry (in-list entries)])
        (define samples (filter (lambda (p) (eq? entry (gallery-probe-entry p))) points))
        (check-true (ormap (lambda (p) (eq? 'read (gallery-probe-kind p))) samples))
        (check-true (ormap (lambda (p) (eq? 'result (gallery-probe-kind p))) samples))
        (for ([point (in-list samples)])
          (check-true (<= (gallery-entry-start entry) (gallery-probe-time point)))
          (check-true (< (gallery-probe-time point) (gallery-entry-end entry)))
          (check-equal (gallery-probe-time point)
                       (+ (gallery-entry-start entry) (gallery-probe-local-time point)))))
      (check-true (> (length points) (length (gallery-review-points entries #:dense? #f))))
      (for ([point (in-list points)])
        (check-true (string? (gallery-probe-id point)) 'stable-probe-id)
        (check-equal (length (gallery-probe-regression-key point)) 8 'semantic-probe-key))
      (define cancellation-samples
        (filter (lambda (point)
                  (and (gallery-probe-phase point)
                       (memq (scheduled-phase-kind (gallery-probe-phase point))
                             '(compact reveal-created))))
                points))
      (for ([fraction '(1/20 3/20 1/4 1/2 3/4 17/20 19/20)])
        (check-true (ormap (lambda (point) (equal? (gallery-probe-fraction point) fraction))
                            cancellation-samples)
                    (list 'dense-cancellation-fraction fraction)))
      (for ([entry (in-list entries)] [next (in-list (cdr entries))])
        (check-equal (gallery-entry-end entry) (gallery-entry-start next)))
      (check-equal (gallery-entry-end (last entries)) (gallery-duration gallery-plates))))
  (test-group "gallery: every plate compiles and cleans its native ids"
    (lambda ()
      (parameterize ([current-native-loader gallery-test-loader]
                     [current-math-typesetter synthetic-typesetter])
        (define entries (gallery-entries gallery-plates))
        (define camera (make-gallery-camera! 1280 720 'dark))
        (define prepared (prepare-gallery-views! entries camera 'dark #:show-api? #t))
        (for ([entry (in-list entries)] [prep (in-list prepared)])
          (define scene (build-gallery-scene! (list entry) (list prep) camera #:show-api? #t))
          (check-close (scene-duration scene) (- (gallery-entry-end entry) (gallery-entry-start entry)))
          (check-equal (hash-count (scene-visuals scene)) 0 (list 'visual-cleanup (gallery-view-key entry)))
          (check-equal (hash-count (scene-data scene)) 0 (list 'scalar-cleanup (gallery-view-key entry))))
        (define combined (build-gallery-scene! entries prepared camera #:show-api? #t))
        (check-close (scene-duration combined) (gallery-duration gallery-plates))
        (check-equal (hash-count (scene-visuals combined)) 0)
        (check-equal (hash-count (scene-data combined)) 0)
        (for ([entry (in-list entries)] [prep (in-list prepared)])
          (define single (build-gallery-scene! (list entry) (list prep) camera #:show-api? #t))
          (define corresponding
            (for/list ([c (in-list (scene-clips combined))]
                         #:when (and (<= (gallery-entry-start entry) (clip-start c))
                                     (< (clip-start c) (gallery-entry-end entry))))
              (struct-copy clip c [start (- (clip-start c) (gallery-entry-start entry))])))
          (check-equal corresponding (scene-clips single) (list 'independent-view-parity (gallery-view-key entry))))
        (for ([clip (in-list (scene-clips combined))])
          (define ids (hash-keys (clip-before clip)))
          (define owners
            (remove-duplicates (map (lambda (id) (take (regexp-split #rx"[.]" (symbol->string id)) 3)) ids)))
          (check-true (<= (length owners) 1) 'no-cross-plate-leak))
        (check-true
          (for/or ([clip (in-list (scene-clips combined))])
            (for/or ([visual (in-hash-values (clip-before clip))])
              (and (eq? (visual-kind visual) 'text)
                   (regexp-match? #rx"^> " (car (visual-content visual)))))) 'active-tree-indicator))))
  (test-group "gallery: implicit unit cancellation moves one target-relative product"
    (lambda ()
      (parameterize ([current-native-loader gallery-test-loader]
                     [current-math-typesetter synthetic-typesetter])
        (define entry
          (car (gallery-entries (select-gallery-plates #:plates '(factor-cancellation)))))
        (define camera (make-gallery-camera! 1280 720 'dark))
        (define prepared (prepare-gallery-view! entry camera 'dark))
        (define scene (build-gallery-scene! (list entry) (list prepared) camera))
        (define (created-request? request)
          (regexp-match? #rx"[.]new[0-9]+[.]" (symbol->string (request-id request))))
        (define product-clip
          (for/first ([clip (in-list (scene-clips scene))]
                      #:when
                      (let ([moves (filter (lambda (request) (eq? (request-kind request) 'move))
                                           (clip-requests clip))])
                        (and (ormap created-request? moves)
                             (ormap (lambda (request) (not (created-request? request))) moves))))
            clip))
        (check-true product-clip 'unit-product-has-one-coherent-move)
        (define moves (filter (lambda (request) (eq? (request-kind request) 'move))
                              (clip-requests product-clip)))
        (define one (findf created-request? moves))
        (define x (findf (lambda (request) (not (created-request? request))) moves))
        (define before (clip-before product-clip))
        (define one-before (visual-position (hash-ref before (request-id one))))
        (define x-before (visual-position (hash-ref before (request-id x))))
        (define one-after (request-value one))
        (define x-after (request-value x))
        (check-equal (- (point-x one-before) (point-x x-before))
                     (- (point-x one-after) (point-x x-after))
                     'unit-and-survivor-keep-target-relative-x)
        (check-equal (- (point-y one-before) (point-y x-before))
                     (- (point-y one-after) (point-y x-after))
                     'unit-and-survivor-keep-target-relative-y))))
  (test-group "gallery: frozen measured body clears every reserved region"
    (lambda ()
      (parameterize ([current-native-loader gallery-test-loader]
                     [current-math-typesetter synthetic-typesetter])
        (define entries (gallery-entries gallery-plates))
        (for* ([theme '(light dark)] [show-api? '(#f #t)])
          (define camera (make-gallery-camera! 1280 720 theme))
          (define preparations (prepare-gallery-views! entries camera theme #:show-api? show-api?))
          (for ([entry (in-list entries)] [prepared-view (in-list preparations)])
            (define prepared (prepared-gallery-view-math prepared-view))
            (define layout (prepared-gallery-view-layout prepared-view))
            (define body (gallery-layout-body layout))
            (define explain-states
              (for/list ([phase (in-list (prepared-math-plan-schedule prepared))]
                         #:when (eq? (scheduled-phase-kind phase) 'explain))
                (car (presentation-phase-annotation (scheduled-phase-phase phase)))))
            (for ([formula (in-hash-values (prepared-math-plan-layouts prepared))]
                  #:unless (member (prepared-layout-state formula) explain-states))
              (for ([token (in-list (prepared-layout-tokens formula))])
                (check-true (>= (- (prepared-token-x token) (/ (prepared-token-width token) 2))
                                (car body))
                            (list 'body-left (gallery-view-key entry)))
                (check-true (<= (+ (prepared-token-x token) (/ (prepared-token-width token) 2))
                                (caddr body))
                            (list 'body-right (gallery-view-key entry)))
                (check-true (<= (+ (prepared-token-y token) (gallery-layout-row-origin layout)
                                   (/ (prepared-token-height token) 2))
                                (cadddr body))
                            (list 'body-top (gallery-view-key entry)))
                (check-true (>= (+ (prepared-token-y token) (gallery-layout-row-origin layout)
                                   (- (* (sub1 (prepared-math-plan-max-rows prepared))
                                         (prepared-math-plan-row-gap prepared)))
                                   (- (/ (prepared-token-height token) 2)))
                                (cadr body))
                            (list 'body-bottom (gallery-view-key entry)))))
            (for ([heading (in-list (gallery-layout-headings layout))])
              (check-true (> (gallery-text-y heading) (cadddr body))
                          (list 'header-above-body (gallery-view-key entry))))
            (check-true (< (gallery-text-y (gallery-layout-caption layout)) (cadr body))
                        (list 'caption-below-body (gallery-view-key entry)))
            (check-equal (and (gallery-layout-api layout) #t) show-api?
                         (list 'api-in-frozen-layout (gallery-view-key entry))))))))
  (test-group "gallery: portable files, fresh builders, and shared-project declarations"
    (lambda ()
      (define root (make-temporary-file "math-gallery-test-~a" 'directory))
      (dynamic-wind void
        (lambda ()
          (define asset (build-path root "fixture.svg"))
          (call-with-output-file asset (lambda (out) (display "<svg xmlns='http://www.w3.org/2000/svg'/>" out)))
          (define options (fixture-options '(additive-cancellation nested-moves explanatory-inset)))
          (define context (fixture-context root))
          (parameterize ([current-native-loader gallery-test-loader]
                         [current-math-typesetter (fixture-typesetter (path->string asset))])
            (define count 0)
            (define preparation
              (parameterize ([current-math-preparation-observer (lambda (_) (set! count (add1 count)))])
                (gallery-render-preparer context options)))
            (check-equal count 3 'one-prepare-per-selected-view)
            (check-equal (length (hash-ref preparation 'dependencies)) 2 'both-runtime-closures-declared)
            (check-equal (hash-ref (hash-ref preparation 'diagnostics) 'gallery-preparation-count) 1)
            (define payload (hash-ref preparation 'payload))
            (define before (canonical-gallery-text payload))
            (define second (gallery-render-preparer context options))
            (check-equal before (canonical-gallery-text (hash-ref second 'payload)) 'stable-portable-identity)
            (parameterize ([current-math-typesetter expect-no-preparation]
                           [current-math-preparation-observer expect-no-preparation])
              (define first-scene (gallery-render-builder context options payload))
              (define second-scene (gallery-render-builder context options payload))
              (check-equal first-scene second-scene 'deterministic-builder)
              (check-close (scene-duration first-scene)
                           (gallery-duration (select-gallery-plates #:plates (hash-ref options 'plates)))))
            (check-raises (lambda () (gallery-render-builder context options (hash-set payload 'schema 'wrong))) #rx"schema")
            (check-raises (lambda () (gallery-render-options context (hash-set options 'workers 10))) #rx"snapshot")
            (check-raises (lambda () (gallery-render-options context (hash-set options 'width 640))) #rx"configuration")
            (define descriptor (hash-ref (vector-ref (hash-ref payload 'views) 0) 'payload))
            (check-raises (lambda () (read-gallery-payload! (hash-set descriptor 'sha1 (make-string 40 #\0)) root)) #rx"digest")
            (check-raises (lambda () (read-gallery-payload! (hash-set descriptor 'byte-count 1) root)) #rx"byte count")
            (check-raises (lambda () (read-gallery-payload! (hash-set descriptor 'path (path->string asset)) root)) #rx"inside")
            (for ([color-key '(foreground background)])
              (define saved-payload (read-gallery-payload! descriptor root))
              (define changed-descriptor
                (write-gallery-payload!
                 (hash-set saved-payload 'math
                           (hash-set (hash-ref saved-payload 'math) color-key "#BADBAD"))
                 root))
              (define changed-views
                (vector->immutable-vector
                  (for/vector ([view (in-vector (hash-ref payload 'views))] [i (in-naturals)])
                    (if (zero? i) (hash-set view 'payload changed-descriptor) view))))
              (check-raises (lambda () (gallery-render-builder context options
                                            (hash-set payload 'views changed-views))) #rx"colors differ"))
            (define saved (file->bytes (hash-ref descriptor 'path)))
            (call-with-output-file (hash-ref descriptor 'path) #:exists 'truncate/replace (lambda (out) (display "broken" out)))
            (check-raises (lambda () (gallery-render-builder context options payload)) #rx"byte count")
            (call-with-output-file (hash-ref descriptor 'path) #:exists 'truncate/replace (lambda (out) (write-bytes saved out)))
            (for ([workers '(1 2 10)])
              (define project (make-gallery-project! (select-gallery-plates #:plates '(both-sides))
                                                     (build-path root "frames") 'dark 30 workers 1280 720 1 #f))
              (define keywords (hash-ref project 'keywords))
              (define rendering (hash-ref (hash-ref keywords '#:render) 'keywords))
              (check-equal (hash-ref rendering '#:workers) workers)
              (check-equal (hash-ref rendering '#:worker-mode) 'auto)
              (define execution (render-gallery-frames! (select-gallery-plates #:plates '(both-sides))
                                      (build-path root "frames") 'dark 30 workers 1280 720 1 #f))
              (check-equal (hash-ref execution 'kind) 'render-project! 'correct-execution-module)
              (check-equal (hash-ref (car (hash-ref execution 'positional)) 'kind) 'animate-project)
              (define source (hash-ref (hash-ref keywords '#:source) 'keywords))
              (check-false (hash-has-key? (hash-ref source '#:options) 'workers)))))
        (lambda () (delete-directory/files root))))))
