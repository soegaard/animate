#lang racket/base

;;;
;;; Versioned Render Worker Protocol
;;;

;; Defines the bounded, reader-safe messages shared by preview today and frame
;; export in later stages.  This module is pure: it owns no processes, ports,
;; scenes, or renderer state.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/math
         racket/port
         "render-frame-job.rkt"
         "render-preparation-manifest.rkt"
         "render-source-model.rkt")

;; Exports
(provide render-worker-protocol-version
         render-worker-maximum-message-bytes
         (struct-out render-worker-module-value-source)
         (struct-out render-worker-module-builder-source)
         (struct-out render-worker-build-context)
         (struct-out render-worker-hello)
         (struct-out render-worker-load-source)
         (struct-out render-worker-source-ready)
         (struct-out render-worker-render-preview-frame)
         (struct-out render-worker-frame-started)
         (struct-out render-worker-frame-complete)
         (struct-out render-worker-render-final-frame)
         (struct-out render-worker-final-frame-complete)
         (struct-out render-worker-failed)
         (struct-out render-worker-cancel)
         (struct-out render-worker-shutdown)
         (struct-out render-worker-stopped)
         (struct-out render-worker-log)
         (struct-out exn:fail:render-worker-protocol)
         render-worker-source?
         render-worker-message?
         render-worker-request?
         render-worker-response?
         render-worker-message-valid?
         render-worker-message-session-id
         render-worker-message-source-fingerprint
         render-worker-message-generation
         render-worker-message-request-id
         render-worker-message-matches?
         write-render-worker-message!
         read-render-worker-message)


;;;
;;; Protocol Constants and Data
;;;

; render-worker-protocol-version : exact-positive-integer?
;;   Identifies the only wire format accepted by this worker implementation.
(define render-worker-protocol-version 4)

; render-worker-maximum-message-bytes : exact-positive-integer?
;;   Bounds one framed protocol payload before the reader allocates its datum.
(define render-worker-maximum-message-bytes (* 32 1024 1024))

; render-worker-header-byte-count : exact-positive-integer?
;;   Stores one hexadecimal payload length before each reader-safe datum.
(define render-worker-header-byte-count 8)

; render-worker-maximum-data-depth : exact-positive-integer?
;;   Allows complete current appearance data while bounding hostile nesting.
(define render-worker-maximum-data-depth 256)

; render-worker-maximum-data-nodes : exact-positive-integer?
;;   Limits structural work before framing imposes the final byte cap.
(define render-worker-maximum-data-nodes 262144)

(struct exn:fail:render-worker-protocol exn:fail (reason)
  #:transparent)

;; exn:fail:render-worker-protocol reports a malformed, oversized, or
;; unsupported message without exposing a reader extension to worker code.

;; Every message starts with these five fields in this exact order:
;; version, session-id, source-fingerprint, generation, request-id.  The
;; common identity lets both sides reject a late reply from a prior generation.
(struct render-worker-module-value-source (module-path binding)
  #:prefab)
(struct render-worker-module-builder-source
  (module-path binding options prepare seed context preparation-manifest)
  #:prefab)
(struct render-worker-build-context
  (asset-base assets width height camera-policy theme-datum typography-datum
              fps quality seed base-fingerprint)
  #:prefab)

;; render-worker-module-value-source describes one ordinary module value.
;;  - module-path  string?  normalized source module path.
;;  - binding      symbol?  exported Scene/timeline/program value.
;;
;; render-worker-module-builder-source describes one PR-A builder source.
;;  - module-path/binding/options/prepare/seed  match module-builder-source.
;;  - context  render-worker-build-context?  transfer-only construction input.
;;  - preparation-manifest  completed parent preparation or #f; a worker
;;                          verifies it before the shared loader invokes builder.
;;
;; render-worker-build-context contains only encoded source-build inputs.
;;  - theme-datum/typography-datum are complete appearance snapshots decoded in
;;    the child before invoking the documented PR-A loader.

(struct render-worker-hello
  (version session-id source-fingerprint generation request-id
           racket-path animate-main-path)
  #:prefab)
(struct render-worker-load-source
  (version session-id source-fingerprint generation request-id source final-output-root input-manifest)
  #:prefab)
(struct render-worker-source-ready
  (version session-id source-fingerprint generation request-id source-summary)
  #:prefab)
(struct render-worker-render-preview-frame
  (version session-id source-fingerprint generation request-id
           sample pixel-scale supersample theme-datum typography-datum
           camera3d-overrides)
  #:prefab)
(struct render-worker-frame-started
  (version session-id source-fingerprint generation request-id)
  #:prefab)
(struct render-worker-frame-complete
  (version session-id source-fingerprint generation request-id
           png-bytes diagnostics)
  #:prefab)
(struct render-worker-render-final-frame
  (version session-id source-fingerprint generation request-id
           source-frame-index output-frame-index fps camera-datum supersample
           theme-datum typography-datum renderer-kind renderer-inputs
           output-name)
  #:prefab)
(struct render-worker-final-frame-complete
  (version session-id source-fingerprint generation request-id
           source-frame-index output-frame-index output-name width height
           byte-count diagnostics)
  #:prefab)
(struct render-worker-failed
  (version session-id source-fingerprint generation request-id phase message)
  #:prefab)
(struct render-worker-cancel
  (version session-id source-fingerprint generation request-id reason)
  #:prefab)
(struct render-worker-shutdown
  (version session-id source-fingerprint generation request-id)
  #:prefab)
(struct render-worker-stopped
  (version session-id source-fingerprint generation request-id reason)
  #:prefab)
(struct render-worker-log
  (version session-id source-fingerprint generation request-id level message)
  #:prefab)

;; render-worker-* messages are immutable prefab records so a bounded reader
;; can reconstruct only the declared protocol grammar.  PNG bytes remain the
;; preview transport. Final workers receive only parent-assigned local output
;; names and return file metadata; no bitmap or final PNG bytes cross the wire.


;;;
;;; Message Validation
;;;

; render-worker-source? : any/c -> boolean?
;;   Recognizes one validated module reconstruction declaration on the wire.
(define (render-worker-source? value)
  (cond
    [(render-worker-module-value-source? value)
     (and (bounded-string? (render-worker-module-value-source-module-path value))
          (symbol? (render-worker-module-value-source-binding value)))]
    [(render-worker-module-builder-source? value)
     (and (bounded-string? (render-worker-module-builder-source-module-path value))
          (symbol? (render-worker-module-builder-source-binding value))
          (hash? (render-worker-module-builder-source-options value))
          (source-transfer-data?
           (render-worker-module-builder-source-options value))
          (or (not (render-worker-module-builder-source-prepare value))
              (symbol? (render-worker-module-builder-source-prepare value)))
          (source-build-seed? (render-worker-module-builder-source-seed value))
          (render-worker-build-context?
           (render-worker-module-builder-source-context value))
          (render-worker-build-context-valid?
           (render-worker-module-builder-source-context value))
          (or (not (render-worker-module-builder-source-preparation-manifest value))
              (render-preparation-manifest?
               (render-worker-module-builder-source-preparation-manifest value))))]
    [else #f]))

; render-worker-message? : any/c -> boolean?
;;   Recognizes one request or response record in the frozen protocol grammar.
(define (render-worker-message? value)
  (or (render-worker-hello? value)
      (render-worker-load-source? value)
      (render-worker-source-ready? value)
      (render-worker-render-preview-frame? value)
      (render-worker-frame-started? value)
      (render-worker-frame-complete? value)
      (render-worker-render-final-frame? value)
      (render-worker-final-frame-complete? value)
      (render-worker-failed? value)
      (render-worker-cancel? value)
      (render-worker-shutdown? value)
      (render-worker-stopped? value)
      (render-worker-log? value)))

; render-worker-request? : any/c -> boolean?
;;   Recognizes one parent-to-child protocol request.
(define (render-worker-request? value)
  (or (render-worker-hello? value)
      (render-worker-load-source? value)
      (render-worker-render-preview-frame? value)
      (render-worker-render-final-frame? value)
      (render-worker-cancel? value)
      (render-worker-shutdown? value)))

; render-worker-response? : any/c -> boolean?
;;   Recognizes one child-to-parent protocol response.
(define (render-worker-response? value)
  (or (render-worker-hello? value)
      (render-worker-source-ready? value)
      (render-worker-frame-started? value)
      (render-worker-frame-complete? value)
      (render-worker-final-frame-complete? value)
      (render-worker-failed? value)
      (render-worker-stopped? value)
      (render-worker-log? value)))

; render-worker-message-valid? : any/c -> boolean?
;;   Checks version, identity, and payload bounds before a message is accepted.
(define (render-worker-message-valid? value)
  (and (render-worker-message? value)
       (render-worker-common-fields-valid? value)
       (cond
         [(render-worker-hello? value)
          (and (bounded-string? (render-worker-hello-racket-path value))
               (bounded-string? (render-worker-hello-animate-main-path value)))]
         [(render-worker-load-source? value)
          (and (render-worker-source? (render-worker-load-source-source value))
               (or (not (render-worker-load-source-final-output-root value))
                   (bounded-string?
                    (render-worker-load-source-final-output-root value)))
               (or (not (render-worker-load-source-input-manifest value))
                   (render-input-manifest?
                    (render-worker-load-source-input-manifest value))))]
         [(render-worker-source-ready? value)
          (protocol-transfer-data?
           (render-worker-source-ready-source-summary value))]
         [(render-worker-render-preview-frame? value)
          (and (preview-sample-datum?
                (render-worker-render-preview-frame-sample value))
               (positive-finite-real?
                (render-worker-render-preview-frame-pixel-scale value))
               (exact-positive-integer?
                (render-worker-render-preview-frame-supersample value))
               (protocol-transfer-data?
                (render-worker-render-preview-frame-theme-datum value))
               (protocol-transfer-data?
                (render-worker-render-preview-frame-typography-datum value))
               (protocol-transfer-data?
                (render-worker-render-preview-frame-camera3d-overrides value)))]
         [(render-worker-frame-complete? value)
          (and (bytes? (render-worker-frame-complete-png-bytes value))
               (<= (bytes-length (render-worker-frame-complete-png-bytes value))
                   render-worker-maximum-message-bytes)
           (protocol-transfer-data?
                (render-worker-frame-complete-diagnostics value)))]
         [(render-worker-render-final-frame? value)
          (and (exact-nonnegative-integer?
                (render-worker-render-final-frame-source-frame-index value))
               (exact-nonnegative-integer?
                (render-worker-render-final-frame-output-frame-index value))
               (exact-positive-integer?
                (render-worker-render-final-frame-fps value))
               (final-render-camera-datum?
                (render-worker-render-final-frame-camera-datum value))
               (exact-positive-integer?
                (render-worker-render-final-frame-supersample value))
               (protocol-transfer-data?
                (render-worker-render-final-frame-theme-datum value))
               (protocol-transfer-data?
                (render-worker-render-final-frame-typography-datum value))
               (eq? (render-worker-render-final-frame-renderer-kind value)
                    'default)
               (empty-immutable-hash?
                (render-worker-render-final-frame-renderer-inputs value))
               (equal?
                (render-worker-render-final-frame-output-name value)
                (final-render-output-name
                 (render-worker-render-final-frame-output-frame-index value))))]
         [(render-worker-final-frame-complete? value)
          (and (exact-nonnegative-integer?
                (render-worker-final-frame-complete-source-frame-index value))
               (exact-nonnegative-integer?
                (render-worker-final-frame-complete-output-frame-index value))
               (equal?
                (render-worker-final-frame-complete-output-name value)
                (final-render-output-name
                 (render-worker-final-frame-complete-output-frame-index value)))
               (exact-positive-integer?
                (render-worker-final-frame-complete-width value))
               (exact-positive-integer?
                (render-worker-final-frame-complete-height value))
               (exact-positive-integer?
                (render-worker-final-frame-complete-byte-count value))
               (protocol-transfer-data?
                (render-worker-final-frame-complete-diagnostics value)))]
         [(render-worker-failed? value)
          (and (symbol? (render-worker-failed-phase value))
               (bounded-string? (render-worker-failed-message value)))]
         [(render-worker-cancel? value)
          (protocol-transfer-data? (render-worker-cancel-reason value))]
        [(render-worker-stopped? value)
          (protocol-transfer-data? (render-worker-stopped-reason value))]
         [(render-worker-log? value)
          (and (memq (render-worker-log-level value) '(debug info warning error))
               (bounded-string? (render-worker-log-message value)))]
         [else #t])))

; render-worker-message-session-id : render-worker-message? -> string?
;;   Returns the common session identifier from one validated message.
(define (render-worker-message-session-id value)
  (render-worker-message-field 'render-worker-message-session-id value 2))

; render-worker-message-source-fingerprint : render-worker-message? -> transfer-data?
;;   Returns the common source/build identity from one validated message.
(define (render-worker-message-source-fingerprint value)
  (render-worker-message-field 'render-worker-message-source-fingerprint value 3))

; render-worker-message-generation : render-worker-message? -> exact-nonnegative-integer?
;;   Returns the common worker generation from one validated message.
(define (render-worker-message-generation value)
  (render-worker-message-field 'render-worker-message-generation value 4))

; render-worker-message-request-id : render-worker-message? -> exact-nonnegative-integer?
;;   Returns the common request identity from one validated message.
(define (render-worker-message-request-id value)
  (render-worker-message-field 'render-worker-message-request-id value 5))

; render-worker-message-matches? : render-worker-message? string? any/c
;                                 exact-nonnegative-integer? exact-nonnegative-integer?
;                                 -> boolean?
;;   Checks whether one response belongs to the current session/generation/request.
(define (render-worker-message-matches? value session-id source-fingerprint generation request-id)
  (and (render-worker-message-valid? value)
       (equal? (render-worker-message-session-id value) session-id)
       (equal? (render-worker-message-source-fingerprint value) source-fingerprint)
       (= (render-worker-message-generation value) generation)
       (= (render-worker-message-request-id value) request-id)))

; render-worker-build-context-valid? : render-worker-build-context? -> boolean?
;;   Validates transferable construction inputs before a child reconstructs them.
(define (render-worker-build-context-valid? context)
  (and (bounded-string? (render-worker-build-context-asset-base context))
       (protocol-transfer-data? (render-worker-build-context-assets context))
       (exact-positive-integer? (render-worker-build-context-width context))
       (exact-positive-integer? (render-worker-build-context-height context))
       (protocol-transfer-data? (render-worker-build-context-camera-policy context))
       (protocol-transfer-data? (render-worker-build-context-theme-datum context))
       (protocol-transfer-data? (render-worker-build-context-typography-datum context))
       (exact-positive-integer? (render-worker-build-context-fps context))
       (symbol? (render-worker-build-context-quality context))
       (source-build-seed? (render-worker-build-context-seed context))
       (bounded-string? (render-worker-build-context-base-fingerprint context))))

; render-worker-common-fields-valid? : render-worker-message? -> boolean?
;;   Validates the fixed identity prefix shared by every protocol record.
(define (render-worker-common-fields-valid? value)
  (and (= (render-worker-message-field 'render-worker-common-fields-valid? value 1)
          render-worker-protocol-version)
       (bounded-string? (render-worker-message-session-id value))
       (source-transfer-data? (render-worker-message-source-fingerprint value))
       (exact-nonnegative-integer? (render-worker-message-generation value))
       (exact-nonnegative-integer? (render-worker-message-request-id value))))

; render-worker-message-field : symbol? render-worker-message? exact-positive-integer? -> any/c
;;   Reads one shared prefab field only after confirming the declared message type.
(define (render-worker-message-field who value field-index)
  (unless (render-worker-message? value)
    (raise-argument-error who "render-worker-message?" value))
  (vector-ref (struct->vector value) field-index))

; preview-sample-datum? : any/c -> boolean?
;;   Recognizes the exact serialized preview sample forms accepted by the child.
(define (preview-sample-datum? value)
  (or (and (list? value)
           (= (length value) 3)
           (eq? (car value) 'frame)
           (exact-nonnegative-integer? (cadr value))
           (exact-positive-integer? (caddr value)))
      (and (list? value)
           (= (length value) 2)
           (eq? (car value) 'time)
           (nonnegative-finite-real? (cadr value)))))

; bounded-string? : any/c -> boolean?
;;   Recognizes a source-transfer string subject to the shared scalar limit.
(define (bounded-string? value)
  (and (string? value) (source-transfer-data? value)))

; positive-finite-real? : any/c -> boolean?
;;   Recognizes a finite positive numeric protocol setting.
(define (positive-finite-real? value)
  (and (protocol-transfer-data? value) (real? value) (positive? value)))

; nonnegative-finite-real? : any/c -> boolean?
;;   Recognizes one finite preview time, including the exact initial sample.
(define (nonnegative-finite-real? value)
  (and (protocol-transfer-data? value) (real? value) (not (negative? value))))

; protocol-transfer-data? : any/c -> boolean?
;;   Recognizes bounded acyclic reader data, including complete color-theme datums.
(define (protocol-transfer-data? value)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (define active (make-hasheq))
    (define node-count 0)
    (define (visit item depth)
      (set! node-count (add1 node-count))
      (when (> node-count render-worker-maximum-data-nodes)
        (raise-arguments-error
         'protocol-transfer-data? "bounded protocol data"
         "maximum-node-count" render-worker-maximum-data-nodes))
      (when (> depth render-worker-maximum-data-depth)
        (raise-arguments-error
         'protocol-transfer-data? "bounded protocol data"
         "maximum-depth" render-worker-maximum-data-depth))
      (cond
        [(or (null? item) (boolean? item) (symbol? item) (keyword? item)
             (char? item)) #t]
        [(and (real? item) (not (nan? item)) (not (infinite? item))) #t]
        [(string? item)
         (<= (string-length item) render-worker-maximum-message-bytes)]
        [(bytes? item)
         (<= (bytes-length item) render-worker-maximum-message-bytes)]
        [(or (pair? item) (vector? item) (hash? item))
         (when (hash-ref active item #f)
           (raise-arguments-error
            'protocol-transfer-data? "acyclic protocol data" "value" item))
         (hash-set! active item #t)
         (define result
           (cond
             [(pair? item)
              (and (visit (car item) (add1 depth))
                   (visit (cdr item) (add1 depth)))]
             [(vector? item)
              (for/and ([entry (in-vector item)])
                (visit entry (add1 depth)))]
             [else
              (for/and ([(key entry) (in-hash item)])
                (and (visit key (add1 depth))
                     (visit entry (add1 depth))))]))
         (hash-remove! active item)
         result]
        [else #f]))
    (visit value 0)))

; empty-immutable-hash? : any/c -> boolean?
;;   Recognizes the no-custom-renderer configuration supported by PR-C workers.
(define (empty-immutable-hash? value)
  (and (immutable? value) (hash? value) (zero? (hash-count value))))


;;;
;;; Framed Reader Transport
;;;

; write-render-worker-message! : output-port? render-worker-message? -> void?
;;   Writes one validated message with a bounded hexadecimal byte-length prefix.
(define (write-render-worker-message! output value)
  (unless (output-port? output)
    (raise-argument-error 'write-render-worker-message! "output-port?" output))
  (unless (render-worker-message-valid? value)
    (raise-protocol-error 'write-render-worker-message! "invalid outgoing message"))
  (define payload
    (call-with-output-bytes
     (lambda (port)
       (write value port))))
  (define payload-length (bytes-length payload))
  (when (> payload-length render-worker-maximum-message-bytes)
    (raise-protocol-error 'write-render-worker-message! "outgoing message exceeds the byte limit"))
  (write-bytes (message-length->header payload-length) output)
  (write-bytes payload output)
  (flush-output output))

; read-render-worker-message : input-port? -> (or/c eof-object? render-worker-message?)
;;   Reads one bounded datum with reader extensions disabled and validates its grammar.
(define (read-render-worker-message input)
  (unless (input-port? input)
    (raise-argument-error 'read-render-worker-message "input-port?" input))
  (define header (read-bytes render-worker-header-byte-count input))
  (cond
    [(eof-object? header) eof]
    [(not (= (bytes-length header) render-worker-header-byte-count))
     (raise-protocol-error 'read-render-worker-message "truncated message length header")]
    [else
     (define payload-length (header->message-length header))
     (when (> payload-length render-worker-maximum-message-bytes)
       (raise-protocol-error 'read-render-worker-message "message exceeds the byte limit"))
     (define payload (read-bytes payload-length input))
     (when (or (eof-object? payload) (not (= (bytes-length payload) payload-length)))
       (raise-protocol-error 'read-render-worker-message "truncated message payload"))
     (define value
       (with-handlers ([exn:fail?
                        (lambda (_error)
                          (raise-protocol-error
                           'read-render-worker-message
                           "reader rejected the framed payload"))])
         (call-with-input-bytes
          payload
          (lambda (port)
            (parameterize ([read-accept-reader #f]
                           [read-accept-lang #f]
                           [read-accept-compiled #f]
                           [read-accept-graph #f])
              (define parsed (read port))
              (unless (eof-object? (read port))
                (raise-protocol-error
                 'read-render-worker-message
                 "payload contains more than one datum"))
              parsed)))))
     (unless (render-worker-message-valid? value)
       (raise-protocol-error 'read-render-worker-message "payload is outside the protocol grammar"))
     value]))

; message-length->header : exact-nonnegative-integer? -> bytes?
;;   Encodes one bounded payload length as exactly eight lowercase hex bytes.
(define (message-length->header length)
  (define digits (number->string length 16))
  (unless (<= (string-length digits) render-worker-header-byte-count)
    (raise-protocol-error 'message-length->header "message length does not fit the header"))
  (string->bytes/utf-8
   (string-append
    (make-string (- render-worker-header-byte-count (string-length digits)) #\0)
    digits)))

; header->message-length : bytes? -> exact-nonnegative-integer?
;;   Decodes one strict fixed-width hexadecimal length header.
(define (header->message-length header)
  (define text
    (with-handlers ([exn:fail?
                     (lambda (_error)
                       (raise-protocol-error 'header->message-length "length header is not UTF-8"))])
      (bytes->string/utf-8 header)))
  (unless (regexp-match? #px"^[0-9a-f]{8}$" text)
    (raise-protocol-error 'header->message-length "length header is not lowercase hexadecimal"))
  (define value (string->number text 16))
  (unless (exact-nonnegative-integer? value)
    (raise-protocol-error 'header->message-length "length header is not an exact integer"))
  value)

; raise-protocol-error : symbol? string? -> none/c
;;   Raises one bounded protocol diagnostic without embedding untrusted payload text.
(define (raise-protocol-error who reason)
  (raise
   (exn:fail:render-worker-protocol
    (format "~a: ~a" who reason)
    (current-continuation-marks)
    reason)))
