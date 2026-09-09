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
         load-color-theme!
         write-color-theme!)

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

;; write-color-theme! : color-theme? path-string? -> path-string?
;; Writes the canonical portable spelling for a complete theme datum. The
;; reader also accepts ordinary long Booleans and curly pairs, but output does
;; not depend on a caller's printer preferences.
(define (write-color-theme! theme path)
  (unless (color-theme? theme)
    (raise-argument-error 'write-color-theme! "color-theme?" theme))
  (unless (path-string? path)
    (raise-argument-error 'write-color-theme! "path-string?" path))
  (call-with-output-file
   path
   (lambda (output)
     (parameterize ([print-pair-curly-braces #f]
                    [print-boolean-long-form #f]
                    [print-graph #f]
                    [print-reader-abbreviations #f])
       (write (theme->datum theme) output)
       (newline output)))
   #:exists 'truncate/replace)
  path)

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
  ;; This is a deliberately small lexical scanner, not a second reader.  It
  ;; recognizes the three reader forms emitted by `write` for our data grammar:
  ;; ordinary atoms, strings, and |quoted symbols|.  Delimiters inside a quoted
  ;; symbol are ordinary symbol spelling, not lists or comments.
  (define (ordinary-delimiter? byte)
    (member byte '(9 10 13 32 40 41 91 93 123 125 59 34 124)))
  (define (whitespace? byte) (member byte '(9 10 13 32)))
  (define (abbreviation-byte? byte) (member byte '(39 44 96))) ; ', , and `
  (define (opening-delimiter-close byte)
    (case byte [(40) 41] [(91) 93] [(123) 125] [else #f]))
  (define (closing-delimiter? byte) (member byte '(41 93 125)))
  (define (bytes-at? position spelling)
    (and (<= (+ position (bytes-length spelling)) length)
         (for/and ([index (in-range (bytes-length spelling))])
           (= (bytes-ref snapshot (+ position index))
              (bytes-ref spelling index)))))
  (define (boolean-token-length position)
    (for/or ([spelling (in-list (list #"#true" #"#false" #"#t" #"#f"))])
      (define spelling-length (bytes-length spelling))
      (and (bytes-at? position spelling)
           (or (= (+ position spelling-length) length)
               (ordinary-delimiter?
                (bytes-ref snapshot (+ position spelling-length))))
           spelling-length)))
  (let loop ([position 0] [delimiters '()] [depth 0])
    (cond
      [(= position length)
       (unless (null? delimiters)
         (fail "balanced list delimiters in a theme datum" position))]
      [else
       (define byte (bytes-ref snapshot position))
       (cond
         [(whitespace? byte) (loop (add1 position) delimiters depth)]
         [(= byte 59) ; ordinary line comment
          (let comment-loop ([index (add1 position)])
            (cond [(or (= index length) (= (bytes-ref snapshot index) 10))
                   (loop index delimiters depth)]
                  [else (comment-loop (add1 index))]))]
         [(opening-delimiter-close byte)
          (count-node! position)
          (define next-delimiters
            (cons (opening-delimiter-close byte) delimiters))
          (define next-depth (add1 depth))
          (when (> next-depth maximum-color-theme-reader-depth)
            (fail "a theme datum within the configured reader-depth budget" position))
          (loop (add1 position) next-delimiters next-depth)]
         [(closing-delimiter? byte)
          (when (null? delimiters)
            (fail "balanced list delimiters in a theme datum" position))
          (unless (= byte (car delimiters))
            (fail "matching list delimiters in a theme datum" position))
          (loop (add1 position) (cdr delimiters) (sub1 depth))]
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
                         [(= current 34) (loop (add1 index) delimiters depth)]
                         [else (string-loop (add1 index) (add1 token-length) #f)])]))]
         [(= byte 124) ; |...| quoted symbol, including writer escapes
          (count-node! position)
          (let quoted-symbol-loop ([index (add1 position)] [token-length 0]
                                   [escaped? #f])
            (when (> token-length maximum-color-theme-token-bytes)
              (fail "a quoted symbol within the configured token-length budget" index))
            (cond [(= index length)
                   (fail "a terminated quoted symbol in a theme datum" position)]
                  [else
                   (define current (bytes-ref snapshot index))
                   (cond [escaped?
                          (quoted-symbol-loop (add1 index) (add1 token-length) #f)]
                         [(= current 92)
                          (quoted-symbol-loop (add1 index) (add1 token-length) #t)]
                         [(= current 124) (loop (add1 index) delimiters depth)]
                         [else
                          (quoted-symbol-loop (add1 index) (add1 token-length) #f)])]))]
         [(= byte 35)
          ;; Theme files may use only the Boolean sentinels emitted by
          ;; theme->datum. Both short and long Boolean writer spellings are
          ;; admitted. In particular #(...), #hash, #s and #; are rejected
          ;; before Racket's reader can allocate or discard their payloads.
          (define boolean-length (boolean-token-length position))
          (if boolean-length
              (begin (count-node! position)
                     (loop (+ position boolean-length) delimiters depth))
              (fail "the declarative theme-file grammar without reader dispatch forms" position))]
         [(abbreviation-byte? byte)
          (fail "the declarative theme-file grammar without reader abbreviations" position)]
         [else
          (count-node! position)
          (let token-loop ([index position] [token-length 0] [escaped? #f])
            (when (> token-length maximum-color-theme-token-bytes)
              (fail "a theme token within the configured token-length budget" index))
            (cond [(= index length)
                   (when escaped?
                     (fail "a completed escaped theme token" position))
                   (when (and (= token-length 1)
                              (= (bytes-ref snapshot position) 46)) ; standalone .
                     (fail "the declarative theme-file grammar without dotted lists" position))
                   (loop index delimiters depth)]
                  [escaped? (token-loop (add1 index) (add1 token-length) #f)]
                  [(= (bytes-ref snapshot index) 92)
                   ;; Racket's writer may use an ordinary atom escape for a
                   ;; vertical bar (for example `role\|bar`).
                   (token-loop (add1 index) (add1 token-length) #t)]
                  [(or
                       (ordinary-delimiter? (bytes-ref snapshot index)))
                   (when (and (= token-length 1)
                              (= (bytes-ref snapshot position) 46)) ; standalone .
                     (fail "the declarative theme-file grammar without dotted lists" position))
                   (loop index delimiters depth)]
                  [(abbreviation-byte? (bytes-ref snapshot index))
                   (fail "the declarative theme-file grammar without reader abbreviations"
                         index)]
                  [else (token-loop (add1 index) (add1 token-length) #f)]))])])))

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
