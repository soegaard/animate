#lang racket/base

;;;
;;; Fresh-process Gallery Contract Fixture
;;;
;; Uses real Racket processes and real staged files with synthetic native geometry.
;; The consumer reconstructs every plate without access to a working typesetter.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/file make-directory*)
         (only-in openssl/sha1 bytes->hex-string)
         "gallery-support.rkt"
         "../private/native.rkt" "../private/prepare.rkt" "../private/typeset.rkt"
         "../examples/gallery/model.rkt" "../examples/gallery/catalogue.rkt"
         "../examples/gallery/artifacts.rkt" "../examples/gallery/source.rkt")

; canonical-data : any/c -> any/c
;;   Removes contract-model structure identity and hash traversal order from comparisons.
(define (canonical-data datum)
  (cond [(hash? datum)
         (cons 'hash (sort (for/list ([(key value) (in-hash datum)])
                            (list (canonical-data key) (canonical-data value)))
                          string<? #:key (lambda (entry) (format "~s" (car entry)))))]
        [(pair? datum) (cons (canonical-data (car datum)) (canonical-data (cdr datum)))]
        [(vector? datum) (list->vector (map canonical-data (vector->list datum)))]
        [(struct? datum) (canonical-data (struct->vector datum))]
        [else datum]))

; scene-signature : scene? -> string?
;;   Hashes the complete synthetic clip/request representation, not only the final state.
(define (scene-signature scn)
  (bytes->hex-string (sha256-bytes (open-input-string (format "~s" (canonical-data scn))))))

; forbidden-preparation : any/c ... -> none/c
;;   Fails an independent consumer if it accidentally prepares or typesets any view.
(define (forbidden-preparation . ignored)
  (error 'gallery-process-fixture "consumer must not prepare or typeset"))

; run-gallery-process-fixture! : string? symbol? path-string? -> void?
;;   Produces or consumes a full-gallery payload under one owned fixture asset root.
(define (run-gallery-process-fixture! mode theme directory)
  (define root (path->complete-path directory))
  (define options (fixture-options (map gallery-plate-id gallery-plates) theme))
  (define context (hash-set (fixture-context root) 'theme theme))
  (define manifest-file (build-path root "gallery.rktd"))
  (parameterize ([current-native-loader gallery-test-loader])
    (cond
      [(string=? mode "encode")
       (make-directory* root)
       (define asset (build-path root "fixture.svg"))
       (call-with-output-file asset
         (lambda (out) (display "<svg xmlns='http://www.w3.org/2000/svg'/>" out)))
       (define preparation-count 0)
       (define preparation
         (parameterize ([current-math-typesetter (fixture-typesetter (path->string asset))]
                        [current-math-preparation-observer
                         (lambda (_) (set! preparation-count (add1 preparation-count)))])
           (gallery-render-preparer context options)))
       (unless (= preparation-count 31) (error 'gallery-process-fixture "expected 31 parent preparations"))
       (define payload (hash-ref preparation 'payload))
       (define scn
         (parameterize ([current-math-typesetter forbidden-preparation]
                        [current-math-preparation-observer forbidden-preparation])
           (gallery-render-builder context options payload)))
       (call-with-output-file manifest-file
         (lambda (out)
           (display (canonical-gallery-text (hasheq 'payload payload 'signature (scene-signature scn))) out)))]
      [(string=? mode "decode")
       (define manifest
         (parameterize ([read-accept-reader #f] [read-accept-lang #f]
                        [read-accept-compiled #f] [read-accept-graph #f])
           (call-with-input-file manifest-file (lambda (in) (syntax->datum (read-syntax #f in))))))
       (define scn
         (parameterize ([current-math-typesetter forbidden-preparation]
                        [current-math-preparation-observer forbidden-preparation])
           (gallery-render-builder context options (hash-ref manifest 'payload))))
       (unless (equal? (scene-signature scn) (hash-ref manifest 'signature))
         (error 'gallery-process-fixture "independent consumer changed native contract data"))
       (printf "PASS gallery ~a: 25 plates / 31 views; fresh-process files and scene contract; no consumer typesetting\n" theme)]
      [else (raise-argument-error 'gallery-process-fixture "encode or decode" mode)])))

(module+ main
  (define arguments (current-command-line-arguments))
  (unless (= (vector-length arguments) 3)
    (raise-user-error 'gallery-process-fixture "expected mode, light/dark, owned directory"))
  (define theme (string->symbol (vector-ref arguments 1)))
  (unless (memq theme '(light dark)) (raise-user-error 'gallery-process-fixture "invalid theme"))
  (run-gallery-process-fixture! (vector-ref arguments 0) theme (vector-ref arguments 2)))
