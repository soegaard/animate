#lang racket/base

;;;
;;; Frame and Media Rendering
;;;

;; Provides the effectful rendering boundary. Requiring this module enables
;; PNG output and external FFmpeg invocation; immutable scene construction and
;; sampling remain available from animate itself.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         racket/path
         racket/port
         file/sha1
         "colors.rkt"
         "private/png-renderer.rkt"
         (only-in "private/paint-pict.rkt" paint->draw-color)
         "private/project-execution.rkt"
         "private/section-renderer.rkt"
         "private/video-assembly.rkt"
         "private/video-encoder.rkt")

;; Exports
(provide (all-from-out "private/png-renderer.rkt"
                       "private/section-renderer.rkt"
                       "private/video-assembly.rkt"
                       "private/video-encoder.rkt")
         ;; This parameter is a private test/headless integration seam, not an
         ;; author-facing render API. Complete artifacts are configured through
         ;; output-spec's #:open-after? declaration.
         (except-out (all-from-out "private/project-execution.rkt")
                     current-project-artifact-opener)
         render-color->draw-color
         load-color-theme!)

;; render-color->draw-color : color-spec? -> color%
;; Converts a custom renderer's semantic color with the immutable context
;; installed by the public 2D rendering entry point. Custom renderers do not
;; receive the private context object and cannot mutate a global theme.
(define (render-color->draw-color color)
  (paint->draw-color color))

(define maximum-color-theme-file-bytes (* 1024 1024))
(define maximum-color-theme-reader-depth 128)
(define maximum-color-theme-reader-nodes 100000)
(define maximum-color-theme-token-bytes 4096)

;; load-color-theme! : path-string? -> color-theme?
;; Reads one bounded, versioned data-only theme file at the effectful render
;; boundary. The digest and decoder share the exact same byte snapshot;
;; workers receive the resulting immutable snapshot and never reread the file.
(define (load-color-theme! path)
  (unless (path-string? path)
    (raise-argument-error 'load-color-theme! "path-string?" path))
  (define complete-path (path->complete-path path))
  (define snapshot (read-color-theme-snapshot complete-path))
  (validate-color-theme-snapshot! snapshot complete-path)
  (define source-datum (read-one-color-theme-datum snapshot complete-path))
  (define digest (bytes->hex-string (sha1-bytes snapshot)))
  (define decoded (datum->theme source-datum))
  (define canonical (theme->datum decoded))
  (datum->theme
   (append (take canonical 7)
           (list (format "~a (sha1 ~a)" complete-path digest)))))

(define (read-color-theme-snapshot path)
  ;; Asking for one byte beyond the bound distinguishes a full permitted file
  ;; from an oversized one without trusting a separate, racy `file-size` read.
  (define bytes
    (call-with-input-file
     path
     (lambda (input)
       (read-bytes (add1 maximum-color-theme-file-bytes) input))))
  (define snapshot (if (eof-object? bytes) #"" bytes))
  (when (> (bytes-length snapshot) maximum-color-theme-file-bytes)
    (raise-arguments-error
     'load-color-theme!
     "a theme file no larger than the configured input budget"
     "path" path
     "maximum bytes" maximum-color-theme-file-bytes))
  (bytes->immutable-bytes snapshot))

;; validate-color-theme-snapshot! : immutable-bytes? path? -> void?
;; Applies the deliberately narrow theme-file grammar before the general reader
;; can allocate vectors, hashes, or other compact allocation-expanding forms.
(define (validate-color-theme-snapshot! snapshot path)
  (define length (bytes-length snapshot))
  (define nodes 0)
  (define (fail expected position)
    (raise-arguments-error 'load-color-theme!
                           expected
                           "path" path
                           "byte position" position))
  (define (count-node! position)
    (set! nodes (add1 nodes))
    (when (> nodes maximum-color-theme-reader-nodes)
      (fail "a theme datum within the configured reader-node budget" position)))
  (define (delimiter? byte)
    (or (member byte '(9 10 13 32 40 41 91 93 59 34))
        (= byte 35)))
  (let loop ([position 0] [depth 0])
    (cond
      [(= position length)
       (unless (zero? depth)
         (fail "balanced list delimiters in a theme datum" position))]
      [else
       (define byte (bytes-ref snapshot position))
       (cond
         [(member byte '(9 10 13 32)) (loop (add1 position) depth)]
         [(= byte 59) ; ordinary line comment
          (let comment-loop ([index (add1 position)])
            (cond [(or (= index length) (= (bytes-ref snapshot index) 10))
                   (loop index depth)]
                  [else (comment-loop (add1 index))]))]
         [(or (= byte 40) (= byte 91))
          (count-node! position)
          (define next-depth (add1 depth))
          (when (> next-depth maximum-color-theme-reader-depth)
            (fail "a theme datum within the configured reader-depth budget" position))
          (loop (add1 position) next-depth)]
         [(or (= byte 41) (= byte 93))
          (when (zero? depth)
            (fail "balanced list delimiters in a theme datum" position))
          (loop (add1 position) (sub1 depth))]
         [(= byte 34)
          (count-node! position)
          (let string-loop ([index (add1 position)] [token-length 0] [escaped? #f])
            (when (> token-length maximum-color-theme-token-bytes)
              (fail "a theme string within the configured token-length budget" index))
            (cond [(= index length)
                   (fail "a terminated string in a theme datum" position)]
                  [else
                   (define current (bytes-ref snapshot index))
                   (cond [escaped? (string-loop (add1 index) (add1 token-length) #f)]
                         [(= current 92) (string-loop (add1 index) (add1 token-length) #t)]
                         [(= current 34) (loop (add1 index) depth)]
                         [else (string-loop (add1 index) (add1 token-length) #f)])]))]
         [(= byte 35)
          ;; Theme files may use only the Boolean sentinels emitted by
          ;; theme->datum. In particular #(...), #hash, #s and #; are rejected
          ;; before Racket's reader can allocate or discard their payloads.
          (if (and (< (add1 position) length)
                   (memv (bytes-ref snapshot (add1 position)) '(116 102)))
              (begin (count-node! position) (loop (+ position 2) depth))
              (fail "the declarative theme-file grammar without reader dispatch forms" position))]
         [else
          (count-node! position)
          (let token-loop ([index position] [token-length 0])
            (when (> token-length maximum-color-theme-token-bytes)
              (fail "a theme token within the configured token-length budget" index))
            (cond [(or (= index length) (delimiter? (bytes-ref snapshot index)))
                   (loop index depth)]
                  [else (token-loop (add1 index) (add1 token-length))]))])])))

(define (read-one-color-theme-datum snapshot path)
  (define input (open-input-bytes snapshot))
  (define (read-data)
    ;; Do not inherit a caller's reader extensions, graph notation, compiled
    ;; forms, custom readtable, or #reader/#lang behaviour at this data-only
    ;; boundary. `read` still accepts ordinary comments and whitespace.
    (call-with-default-reading-parameterization
     (lambda ()
       ;; Install the restrictive parameters *after* the default reader
       ;; parameterization, which otherwise deliberately enables graph and
       ;; language forms for ordinary Racket source readers.
       (parameterize ([read-accept-reader #f]
                      [read-accept-lang #f]
                      [read-accept-compiled #f]
                      [read-accept-graph #f]
                      [current-readtable #f])
         (read input)))))
  (define datum (read-data))
  (when (eof-object? datum)
    (raise-arguments-error 'load-color-theme! "a nonempty theme datum" "path" path))
  (define trailing (read-data))
  (unless (eof-object? trailing)
    (raise-arguments-error
     'load-color-theme!
     "a file containing exactly one theme datum"
     "path" path))
  datum)
