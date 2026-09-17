#lang racket/base

;;;
;;; Prepared Mathematical Plan Codec Tests
;;;
;; Exercises the bounded data-only parent/worker layout handoff without TeX,
;; filesystem artifacts, or a native rasterizer.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/vector
         "check.rkt"
         (submod "native-contract.rkt" support)
         "../main.rkt"
         "../private/native.rkt"
         "../private/prepare.rkt"
         "../private/prepared-plan-codec.rkt"
         "../private/typeset.rkt"
         (prefix-in adapter: "../private/animate-adapter.rkt")
         (prefix-in qc: "../examples/quadratic-concrete.rkt"))

(provide run-prepared-plan-codec-tests)


;;;
;;; Fixture Helpers
;;;

; codec-options : immutable-hash?
;;   Declares the complete selected-case/raster snapshot expected by a builder.
(define codec-options
  #hasheq((schema . animate-math-render-options-v1)
           (lesson . quadratic-concrete)
           (case-path . #f)
           (title . "quadratic concrete")
           (theme-mode . dark)
           (width . 160)
           (height . 90)
           (fps . 1)
           (supersample . 1)
           (camera . #hasheq((schema . animate-math-camera-v1)
                              (width . 160)
                              (height . 90)
                              (background . "#121620")))))

; vector-replace : immutable-vector? exact-nonnegative-integer? any/c -> immutable-vector?
;;   Makes one malformed-wire fixture without mutating an accepted payload.
(define (vector-replace entries index value)
  (define copy (vector-copy entries))
  (vector-set! copy index value)
  (vector->immutable-vector copy))

; fixture-prepared-plan : [presentation-plan?] -> prepared-math-plan?
;;   Uses the existing renderer-free contract adapter for deterministic layouts.
(define (fixture-prepared-plan [plan qc:plan])
  (parameterize ([current-native-loader loader]
                 [current-math-typesetter synthetic-typesetter])
    (prepare-math-plan! plan #:theme 'dark)))

; fraction-codec-plan : presentation-plan?
;;   Retains one division owner while the numerator is evaluated.
(define fraction-codec-plan
  (present
   (derive (math '(/ (- 17 5) 3) #:id 'fraction-codec)
     [numerator (evaluate #:at (numerator))]
     [quotient (evaluate)])
   #:style (math-presentation #:history 'replace #:duration 1
                              #:pause-between-groups 0)))


;;;
;;; Codec Rebinding
;;;

; run-prepared-plan-codec-tests : -> void?
;;   Runs codec identity, corruption, and no-typesetter-on-rebind regression checks.
(define (run-prepared-plan-codec-tests)
  (test-group
   "prepared mathematical plan codec"
   (lambda ()
     (define prepared (fixture-prepared-plan))
     (define payload
       (prepared-math-plan->portable-payload
        prepared
        codec-options
        (hash "synthetic-test-asset.svg" "staged-synthetic-test-asset.svg")))
     (define worker-camera ((loader 'animate 'make-camera) #:width 160 #:height 90
                           #:background "#121620"))
     (check-equal (hash-ref payload 'schema) math-preparation-payload-schema 'schema)
     (check-equal (length (portable-payload-artifact-paths payload)) 1 'artifact-list)
     (parameterize
     ([current-native-loader loader]
       [current-math-typesetter
        (lambda _arguments
          (error 'prepared-plan-codec-test "worker rebinding must not typeset"))])
      (define rebound
        (portable-payload->prepared-math-plan payload qc:plan worker-camera codec-options))
      (check-equal (hash-count (prepared-math-plan-layouts rebound))
                   (hash-count (prepared-math-plan-layouts prepared))
                   'complete-layout-coverage)
      (check-equal (prepared-math-plan-row-gap rebound)
                   (prepared-math-plan-row-gap prepared)
                   'frozen-row-gap)
      (check-equal (prepared-math-plan-max-rows rebound)
                   (prepared-math-plan-max-rows prepared)
                   'frozen-visible-rows)
      (check-true (adapter:math-plan->scene! rebound) 'scene-compiles-without-typesetter))
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan
         (hash-set payload 'schema 'wrong-schema) qc:plan worker-camera codec-options))
      #rx"schema"
      'wrong-schema)
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan payload qc:plan worker-camera
                                              (hash-set codec-options 'width 161)))
      #rx"options"
      'wrong-options)
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan
         (hash-set payload 'row-gap 0) qc:plan worker-camera codec-options))
      #rx"positive finite real"
      'invalid-row-gap)
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan
         (hash-set payload 'max-rows 1) qc:plan worker-camera codec-options))
      #rx"visible-row bound"
      'invalid-max-rows)
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan
         (hash-set payload 'layouts (vector->immutable-vector (vector)))
         qc:plan worker-camera codec-options))
      #rx"immutable vector|exactly one prepared layout"
      'missing-layout)
     (define layouts (hash-ref payload 'layouts))
     (define first-layout (vector-ref layouts 0))
     (define tokens (hash-ref first-layout 'tokens))
     (define first-token (vector-ref tokens 0))
     (define bad-token (hash-set first-token 'path '(999)))
     (define bad-layout
       (hash-set first-layout 'tokens (vector-replace tokens 0 bad-token)))
     (check-raises
      (lambda ()
        (portable-payload->prepared-math-plan
         (hash-set payload 'layouts (vector-replace layouts 0 bad-layout))
         qc:plan worker-camera codec-options))
      #rx"occurrence|semantic token span"
      'bad-token-ownership)))
  (test-group
   "prepared mathematical plan codec: persistent fraction bars remain v2 data"
   (lambda ()
     (define prepared (fixture-prepared-plan fraction-codec-plan))
     (define source-entry
       (for*/first ([(state layout) (in-hash (prepared-math-plan-layouts prepared))]
                    [token (in-list (prepared-layout-tokens layout))]
                    #:when (fraction-bar-token? token))
         (cons state token)))
     (define source-state (car source-entry))
     (define source-bar (cdr source-entry))
     (check-true source-bar 'prepared-fraction-bar-present)
     (define payload
       (prepared-math-plan->portable-payload
        prepared
        codec-options
        (hash "synthetic-test-asset.svg" "staged-synthetic-test-asset.svg")))
     (check-equal (hash-ref payload 'schema) math-preparation-payload-schema
                  'fraction-bars-keep-v2-schema)
     (define worker-camera
       ((loader 'animate 'make-camera) #:width 160 #:height 90 #:background "#121620"))
     (parameterize
      ([current-native-loader loader]
       [current-math-typesetter
        (lambda _arguments
          (error 'prepared-plan-codec-test "fraction-bar worker rebinding must not typeset"))])
      (define rebound
        (portable-payload->prepared-math-plan payload fraction-codec-plan worker-camera codec-options))
      (define rebound-bar
        (findf fraction-bar-token?
               (prepared-layout-tokens
                (hash-ref (prepared-math-plan-layouts rebound) source-state))))
      (check-true rebound-bar 'rebound-fraction-bar-present)
      (check-equal (prepared-token-role rebound-bar) (prepared-token-role source-bar)
                   'fraction-bar-role-round-trips)
      (check-equal (prepared-token-path rebound-bar) (prepared-token-path source-bar)
                   'fraction-bar-path-round-trips)
      (check-equal (prepared-token-x rebound-bar) (prepared-token-x source-bar)
                   'fraction-bar-x-round-trips)
      (check-equal (prepared-token-y rebound-bar) (prepared-token-y source-bar)
                   'fraction-bar-y-round-trips)
      (check-equal (prepared-token-width rebound-bar) (prepared-token-width source-bar)
                   'fraction-bar-width-round-trips)
      (check-equal (prepared-token-height rebound-bar) (prepared-token-height source-bar)
                   'fraction-bar-height-round-trips)
      (check-equal (prepared-token-id rebound-bar) (prepared-token-id source-bar)
                   'fraction-bar-id-round-trips)
      (check-equal (prepared-token-asset rebound-bar) "staged-synthetic-test-asset.svg"
                   'fraction-bar-staged-asset-round-trips)
      (check-true (adapter:math-plan->scene! rebound)
                  'rebound-fraction-plan-compiles-without-typesetter)))))
