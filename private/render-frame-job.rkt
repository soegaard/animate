#lang racket/base

;;;
;;; Final Render Frame Jobs
;;;

;; Defines immutable, transport-safe final-render job descriptions.  This
;; module is pure: it contains no Pict, bitmap, filesystem, or process code.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/format
         racket/math
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "render-source-model.rkt")

;; Exports
(provide final-render-frame-job?
         final-render-frame-job-session-id
         final-render-frame-job-source-fingerprint
         final-render-frame-job-generation
         final-render-frame-job-request-id
         final-render-frame-job-source-frame-index
         final-render-frame-job-output-frame-index
         final-render-frame-job-fps
         final-render-frame-job-camera-datum
         final-render-frame-job-supersample
         final-render-frame-job-theme-datum
         final-render-frame-job-typography-datum
         final-render-frame-job-renderer-kind
         final-render-frame-job-renderer-inputs
         final-render-frame-job-output-name
         make-final-render-frame-job
         final-render-frame-job-valid?
         final-render-output-name
         final-render-output-name?
         camera->final-render-datum
         datum->final-render-camera
         final-render-camera-datum?
         final-render-transfer-data?
         final-render-transfer-data-snapshot)


;;;
;;; Data Representation
;;;

(struct final-render-frame-job
  (session-id source-fingerprint generation request-id source-frame-index
              output-frame-index fps camera-datum supersample theme-datum
              typography-datum renderer-kind renderer-inputs output-name)
  #:transparent)

;; final-render-frame-job represents one final PNG request in one worker
;; session.
;;  - session-id/source-fingerprint/generation/request-id are execution
;;    identities.  They never contribute to scene construction or pixels.
;;  - source-frame-index is sampled from the original source frame grid.
;;  - output-frame-index is the zero-based local publication slot.
;;  - fps/camera-datum/supersample/theme-datum/typography-datum freeze the
;;    complete supported software rendering configuration for this job.
;;  - renderer-kind/renderer-inputs describe only transferable renderer setup;
;;    current subprocess workers accept the explicit 'default renderer set and
;;    empty inputs. Shared preparation travels only in the verified source-load
;;    manifest, never in an ambiguous per-frame payload.
;;  - output-name is the parent-assigned, strictly local PNG basename.  It is
;;    derived from output-frame-index, so worker completion order is irrelevant.


;;;
;;; Construction and Validation
;;;

; make-final-render-frame-job : string? transfer-data? exact-nonnegative-integer?
;                                exact-nonnegative-integer? exact-nonnegative-integer?
;                                exact-nonnegative-integer? exact-positive-integer?
;                                [#:camera (or/c camera? false/c)]
;                                [#:supersample exact-positive-integer?]
;                                [#:theme-datum transfer-data?]
;                                [#:typography-datum transfer-data?]
;                                [#:renderer-kind 'default]
;                                [#:renderer-inputs transfer-data?]
;                                -> final-render-frame-job?
;;   Snapshots one supported final-render request without loading or rendering.
(define (make-final-render-frame-job session-id source-fingerprint generation
                                     request-id source-frame-index output-frame-index
                                     fps
                                     #:camera [camera #f]
                                     #:supersample [supersample 1]
                                     #:theme-datum [theme-datum #hasheq()]
                                     #:typography-datum [typography-datum #hasheq()]
                                     #:renderer-kind [renderer-kind 'default]
                                     #:renderer-inputs [renderer-inputs #hasheq()])
  (define output-name (final-render-output-name output-frame-index))
  (define job
    (final-render-frame-job
     (snapshot-session-id 'make-final-render-frame-job session-id)
     (source-transfer-data-snapshot 'make-final-render-frame-job source-fingerprint)
     generation
     request-id
     source-frame-index
     output-frame-index
     fps
     (camera->final-render-datum camera)
     supersample
     (final-render-transfer-data-snapshot 'make-final-render-frame-job theme-datum)
     (final-render-transfer-data-snapshot 'make-final-render-frame-job typography-datum)
     renderer-kind
     (final-render-transfer-data-snapshot 'make-final-render-frame-job renderer-inputs)
     output-name))
  (unless (final-render-frame-job-valid? job)
    (raise-arguments-error
     'make-final-render-frame-job
     "a valid final-render frame job"
     "job" job))
  job)

; final-render-frame-job-valid? : any/c -> boolean?
;;   Recognizes one bounded request that the PR-C software worker can execute.
(define (final-render-frame-job-valid? value)
  (and (final-render-frame-job? value)
       (bounded-session-id? (final-render-frame-job-session-id value))
       (source-transfer-data? (final-render-frame-job-source-fingerprint value))
       (exact-nonnegative-integer? (final-render-frame-job-generation value))
       (exact-nonnegative-integer? (final-render-frame-job-request-id value))
       (exact-nonnegative-integer? (final-render-frame-job-source-frame-index value))
       (exact-nonnegative-integer? (final-render-frame-job-output-frame-index value))
       (exact-positive-integer? (final-render-frame-job-fps value))
       (final-render-camera-datum? (final-render-frame-job-camera-datum value))
       (exact-positive-integer? (final-render-frame-job-supersample value))
       (final-render-transfer-data? (final-render-frame-job-theme-datum value))
       (final-render-transfer-data? (final-render-frame-job-typography-datum value))
       (eq? (final-render-frame-job-renderer-kind value) 'default)
       (empty-immutable-hash? (final-render-frame-job-renderer-inputs value))
       (equal? (final-render-frame-job-output-name value)
               (final-render-output-name
                (final-render-frame-job-output-frame-index value)))))

; final-render-output-name : exact-nonnegative-integer? -> string?
;;   Gives the only worker-owned PNG basename for one local output slot.
(define (final-render-output-name output-frame-index)
  (unless (exact-nonnegative-integer? output-frame-index)
    (raise-argument-error
     'final-render-output-name "exact-nonnegative-integer?" output-frame-index))
  (format "frame-~a.png"
          (~r output-frame-index #:min-width 6 #:pad-string "0")))

; final-render-output-name? : any/c -> boolean?
;;   Recognizes one canonical local PNG basename without path traversal syntax.
(define (final-render-output-name? value)
  (and (string? value)
       (regexp-match? #px"^frame-[0-9]{6,}\\.png$" value)))


;;;
;;; Camera Transfer
;;;

; camera->final-render-datum : (or/c camera? false/c) -> transfer-data?
;;   Converts a supported static camera into reader-safe semantic data.
(define (camera->final-render-datum value)
  (cond
    [(not value) #f]
    [(camera? value)
     (define background (camera-background value))
     (unless (color-spec? background)
       (raise-arguments-error
        'camera->final-render-datum
        "a camera whose background is a transferable color specification"
        "background" background))
     (list 'animate-final-render-camera-v1
           (camera-width value)
           (camera-height value)
           (camera-world-width value)
           (vec2-x (camera-center value))
           (vec2-y (camera-center value))
           (color-spec->datum background))]
    [else
     (raise-argument-error 'camera->final-render-datum "(or/c camera? false/c)" value)]))

; datum->final-render-camera : (or/c transfer-data? false/c) -> (or/c camera? false/c)
;;   Reconstructs a static camera after validating the exact transfer grammar.
(define (datum->final-render-camera value)
  (cond
    [(not value) #f]
    [(and (list? value) (= (length value) 7)
          (eq? (car value) 'animate-final-render-camera-v1))
     (define width (list-ref value 1))
     (define height (list-ref value 2))
     (define world-width (list-ref value 3))
     (define center-x (list-ref value 4))
     (define center-y (list-ref value 5))
     (define background-datum (list-ref value 6))
     (unless (and (exact-positive-integer? width)
                  (exact-positive-integer? height)
                  (finite-positive-real? world-width)
                  (finite-real? center-x)
                  (finite-real? center-y)
                  (final-render-transfer-data? background-datum))
       (raise-arguments-error
        'datum->final-render-camera
        "a valid final-render camera datum"
        "datum" value))
     (make-camera #:width width
                  #:height height
                  #:world-width world-width
                  #:center (vec2 center-x center-y)
                  #:background (datum->color-spec background-datum))]
    [else
     (raise-arguments-error
      'datum->final-render-camera "a final-render camera datum or #f" "datum" value)]))

; final-render-camera-datum? : any/c -> boolean?
;;   Checks a camera datum by attempting its bounded semantic reconstruction.
(define (final-render-camera-datum? value)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (datum->final-render-camera value)
    #t))

; snapshot-session-id : symbol? any/c -> immutable-string?
;;   Copies the execution-only session label before storing it in a job record.
(define (snapshot-session-id who value)
  (unless (bounded-session-id? value)
    (raise-argument-error who "bounded string? as session-id" value))
  (string->immutable-string (string-copy value)))

; bounded-session-id? : any/c -> boolean?
;;   Recognizes the bounded string identity accepted by the worker protocol.
(define (bounded-session-id? value)
  (and (string? value) (source-transfer-data? value)))

; empty-immutable-hash? : any/c -> boolean?
;;   Recognizes the explicit no-custom-renderer configuration supported in PR-C.
(define (empty-immutable-hash? value)
  (and (immutable? value) (hash? value) (zero? (hash-count value))))

; finite-real? : any/c -> boolean?
;;   Recognizes one finite real accepted by the semantic camera model.
(define (finite-real? value)
  (and (real? value) (rational? value)))

; finite-positive-real? : any/c -> boolean?
;;   Recognizes one positive finite camera world width.
(define (finite-positive-real? value)
  (and (finite-real? value) (positive? value)))


;;;
;;; Bounded Appearance and Prepared Data
;;;

; final-render-transfer-data? : any/c -> boolean?
;;   Recognizes immutable-copyable data at the protocol's appearance depth limit.
(define (final-render-transfer-data? value)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (final-render-transfer-data-snapshot 'final-render-transfer-data? value)
    #t))

; final-render-transfer-data-snapshot : symbol? any/c -> immutable-transfer-data?
;;   Copies complete theme, typography, and future preparation data without aliases.
(define (final-render-transfer-data-snapshot who value)
  (unless (symbol? who)
    (raise-argument-error 'final-render-transfer-data-snapshot "symbol?" who))
  (define active (make-hasheq))
  (define node-count 0)
  (define (visit item depth)
    (set! node-count (add1 node-count))
    (when (> node-count 262144)
      (raise-arguments-error
       who "bounded final-render transfer data" "maximum-node-count" 262144))
    (when (> depth 256)
      (raise-arguments-error
       who "final-render transfer data within the nesting limit" "maximum-depth" 256))
    (cond
      [(or (null? item) (boolean? item) (symbol? item) (keyword? item)
           (char? item)) item]
      [(and (real? item) (not (nan? item)) (not (infinite? item))) item]
      [(string? item)
       (check-final-render-scalar-length who "string" (string-length item))
       (string->immutable-string (string-copy item))]
      [(bytes? item)
       (check-final-render-scalar-length who "bytes" (bytes-length item))
       (bytes->immutable-bytes (bytes-copy item))]
      [(or (pair? item) (vector? item) (hash? item))
       (when (hash-has-key? active item)
         (raise-arguments-error who "acyclic final-render transfer data"
                                "cyclic-container" item))
       (hash-set! active item #t)
       (dynamic-wind
        void
        (lambda ()
          (cond
            [(pair? item)
             (cons (visit (car item) (add1 depth))
                   (visit (cdr item) (add1 depth)))]
            [(vector? item)
             (vector->immutable-vector
              (list->vector
               (for/list ([entry (in-vector item)])
                 (visit entry (add1 depth)))))]
            [else
             (for/fold ([copy (empty-immutable-hash-like item)])
                       ([(key entry) (in-hash item)])
               (hash-set copy
                         (visit key (add1 depth))
                         (visit entry (add1 depth))))]))
        (lambda () (hash-remove! active item)))]
      [else
       (raise-arguments-error
        who
        "bounded data made from finite reals, booleans, symbols, keywords, characters, strings, bytes, pairs, vectors, and hashes"
        "value" item)]))
  (visit value 0))

; check-final-render-scalar-length : symbol? string? exact-nonnegative-integer? -> void?
;;   Applies the protocol message scalar limit before copying a large atom.
(define (check-final-render-scalar-length who kind length)
  (when (> length (* 32 1024 1024))
    (raise-arguments-error
     who "a string or byte sequence within the final-render protocol limit"
     "kind" kind "maximum-byte-length" (* 32 1024 1024) "actual-length" length)))

; empty-immutable-hash-like : hash? -> immutable-hash?
;;   Preserves hash equality discipline while removing mutable caller aliases.
(define (empty-immutable-hash-like value)
  (cond
    [(hash-eq? value) #hasheq()]
    [(hash-eqv? value) #hasheqv()]
    [else #hash()]))
