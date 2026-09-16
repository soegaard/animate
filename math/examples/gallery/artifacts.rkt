#lang racket/base

;;;
;;; Portable Gallery Preparation Files
;;;
;; Stores each already prepared replay in a bounded, content-addressed file. The
;; generic source manifest verifies and leases these files with their SVG assets.

;;;
;;; Imports and Exports
;;;
(require file/sha1
         (only-in racket/file file->bytes make-directory* make-temporary-file)
         (only-in racket/path path-only find-relative-path)
         (only-in racket/port call-with-output-string)
         "../../private/preparation-artifacts.rkt")
(provide write-gallery-payload! read-gallery-payload! canonical-gallery-text)

; maximum-gallery-payload-bytes : exact-positive-integer?
;;   Bounds one replay file independently of the generic worker message limit.
(define maximum-gallery-payload-bytes (* 8 1024 1024))

; canonical-gallery-text : any/c -> string?
;;   Writes immutable portable data with sorted hash keys and preserved hash equality mode.
(define (canonical-gallery-text datum)
  (call-with-output-string
    (lambda (out)
      (define (emit value)
        (cond
          [(hash? value)
           (display (cond [(hash-eq? value) "#hasheq("] [(hash-eqv? value) "#hasheqv("] [else "#hash("]) out)
           (for ([key (in-list (sort (hash-keys value) string<? #:key (lambda (k) (format "~s" k))))])
             (display "(" out) (emit key) (display " . " out) (emit (hash-ref value key)) (display ")" out))
           (display ")" out)]
          [(vector? value)
           (display "#(" out)
           (for ([item (in-vector value)]) (emit item) (display " " out))
           (display ")" out)]
          [(pair? value)
           (display "(" out) (emit (car value))
           (let loop ([tail (cdr value)])
             (cond [(null? tail) (void)]
                   [(pair? tail) (display " " out) (emit (car tail)) (loop (cdr tail))]
                   [else (display " . " out) (emit tail)]))
           (display ")" out)]
          [else (write value out)]))
      (emit datum))))

; write-gallery-payload! : immutable-hash? path-string? -> immutable-hash?
;;   Atomically publishes one portable replay and returns its verified content descriptor.
(define (write-gallery-payload! payload asset-base)
  (define content (string->bytes/utf-8 (canonical-gallery-text payload)))
  (unless (<= (bytes-length content) maximum-gallery-payload-bytes)
    (raise-user-error 'write-gallery-payload! "prepared view exceeds the 8 MiB payload limit"))
  (define digest (sha1 (open-input-bytes content)))
  (define root (math-preparation-artifact-directory asset-base))
  (make-directory* root)
  (define path (build-path root (string-append digest ".gallery.rktd")))
  (unless (and (file-exists? path) (equal? (file->bytes path) content))
    (define temporary (make-temporary-file "gallery-~a.tmp" #f root))
    (dynamic-wind void
      (lambda ()
        (call-with-output-file temporary #:exists 'truncate/replace
          (lambda (out) (write-bytes content out)))
        (rename-file-or-directory temporary path #t))
      (lambda () (when (file-exists? temporary) (delete-file temporary)))))
  (hasheq 'path (path->string (path->complete-path path)) 'role 'math-gallery-prepared-plan
          'sha1 digest 'byte-count (bytes-length content)))

; read-gallery-payload! : immutable-hash? path-string? -> immutable-hash?
;;   Verifies ownership and content, then reads exactly one inert portable datum.
(define (read-gallery-payload! descriptor asset-base)
  (unless (and (hash? descriptor) (immutable? descriptor)
               (string? (hash-ref descriptor 'path #f))
               (eq? (hash-ref descriptor 'role #f) 'math-gallery-prepared-plan)
               (string? (hash-ref descriptor 'sha1 #f))
               (regexp-match? #px"^[0-9a-f]{40}$" (hash-ref descriptor 'sha1))
               (exact-positive-integer? (hash-ref descriptor 'byte-count #f))
               (<= (hash-ref descriptor 'byte-count) maximum-gallery-payload-bytes))
    (raise-argument-error 'read-gallery-payload! "bounded gallery payload descriptor" descriptor))
  (define path (simplify-path (path->complete-path (hash-ref descriptor 'path)) #t))
  (define root (simplify-path (path->complete-path (math-preparation-artifact-directory asset-base)) #t))
  (define relative (find-relative-path root path))
  (unless (and (relative-path? relative) (not (member 'up (explode-path relative)))
               (file-exists? path))
    (raise-arguments-error 'read-gallery-payload! "existing payload inside the preparation root" "path" path))
  (unless (= (file-size path) (hash-ref descriptor 'byte-count))
    (raise-arguments-error 'read-gallery-payload! "payload byte count differs" "path" path))
  (define content (file->bytes path))
  (unless (string=? (sha1 (open-input-bytes content)) (hash-ref descriptor 'sha1))
    (raise-arguments-error 'read-gallery-payload! "payload digest differs" "path" path))
  (parameterize ([read-accept-reader #f] [read-accept-lang #f]
                 [read-accept-compiled #f] [read-accept-graph #f])
    (define in (open-input-bytes content))
    (define syntax (read-syntax #f in))
    (define value (and (syntax? syntax) (syntax->datum syntax)))
    (unless (and (hash? value) (eof-object? (read in)))
      (raise-user-error 'read-gallery-payload! "expected exactly one portable payload hash"))
    value))
