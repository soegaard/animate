#lang racket/base

;;;
;;; Fresh-process Prepared Move Fixture
;;;
;; Round-trips a real portable payload between independent Racket processes using
;; synthetic native geometry. This is not actual Animate rasterization or TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (for-syntax racket/base)
         (only-in racket/runtime-path define-runtime-path)
         "../private/presentation.rkt"
         "../private/native.rkt"
         "../private/prepare.rkt"
         "../private/typeset.rkt"
         "../private/prepared-plan-codec.rkt"
         (prefix-in adapter: "../private/animate-adapter.rkt")
         (submod "native-contract.rkt" support))

;;;
;;; Stable Comparison Data
;;;
; example-directory : path?
;;   Resolves the test's actual lesson modules independently of process working directory.
(define-runtime-path example-directory "../examples")

; canonical-data : any/c -> any/c
;;   Converts contract structs and unordered hashes to deterministic comparison data.
(define (canonical-data value)
  (cond
    [(hash? value)
     (cons 'hash
           (sort (for/list ([(key item) (in-hash value)])
                   (list (canonical-data key) (canonical-data item)))
                 string<? #:key (lambda (entry) (format "~s" (car entry)))))]
    [(pair? value) (cons (canonical-data (car value)) (canonical-data (cdr value)))]
    [(vector? value) (list->vector (map canonical-data (vector->list value)))]
    [(struct? value) (canonical-data (struct->vector value))]
    [else value]))

; run-contract-fixture! : string? string? path-string? -> void?
;;   Encodes in one process or consumes in another with preparation explicitly forbidden.
(define (run-contract-fixture! mode lesson file)
  (unless (member lesson '("linear-concrete" "linear-general" "quadratic-concrete" "quadratic-general"))
    (raise-argument-error 'run-contract-fixture! "one of the four lesson names" lesson))
  (define plan (dynamic-require (build-path example-directory (string-append lesson ".rkt")) 'plan))
  (define options (hasheq 'lesson (string->symbol lesson) 'theme 'dark))
  (parameterize ([current-native-loader loader])
    (cond
      [(string=? mode "encode")
       (parameterize ([current-math-typesetter synthetic-typesetter])
         (define prepared (prepare-math-plan! plan #:theme 'dark))
         (define payload (prepared-math-plan->portable-payload
                           prepared options
                           (hash "synthetic-test-asset.svg" "synthetic-test-asset.svg")))
         (define scene (adapter:math-plan->scene! prepared))
         (call-with-output-file file #:exists 'error
           (lambda (port) (write (list payload (canonical-data scene)) port))))]
      [(string=? mode "decode")
       (define data
         (parameterize ([read-accept-reader #f] [read-accept-lang #f]
                        [read-accept-compiled #f] [read-accept-graph #f])
           (call-with-input-file file
             (lambda (port) (syntax->datum (read-syntax #f port))))))
       (define payload (car data))
       (define camera ((loader 'animate 'make-camera) #:background "#121620"))
       (parameterize ([current-math-typesetter
                       (lambda ignored (error 'contract-fixture "worker must not typeset"))]
                      [current-math-preparation-observer
                       (lambda ignored (error 'contract-fixture "worker must not prepare"))])
         (define prepared (portable-payload->prepared-math-plan payload plan camera options))
         (define actual (canonical-data (adapter:math-plan->scene! prepared)))
         (unless (equal? actual (cadr data))
           (error 'contract-fixture "fresh-process native contract differs for ~a" lesson))
         (printf "PASS ~a: fresh-process move paths/layouts/scene contract; no typesetting\n" lesson))]
      [else (raise-argument-error 'run-contract-fixture! "encode or decode" mode)])))

(module+ main
  (define args (current-command-line-arguments))
  (unless (= (vector-length args) 3)
    (raise-user-error 'composite-process-fixture "expected mode, lesson name, and payload file"))
  (run-contract-fixture! (vector-ref args 0) (vector-ref args 1) (vector-ref args 2)))
