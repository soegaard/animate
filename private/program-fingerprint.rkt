#lang racket/base

;;;
;;; Conservative Source Fingerprints for Scene Programs
;;;

;; Fingerprints intentionally describe the *declared source* of a program,
;; not its procedure identities.  This lets a fresh source generation reuse a
;; verified immutable prefix while treating helpers, imports, and anything we
;; cannot locate inside a declared block as ambient code that invalidates the
;; whole program.

(require file/sha1
         racket/file
         racket/list
         racket/path
         "scene-program.rkt")

(provide (struct-out scene-program-fingerprint)
         scene-program-source-path
         fingerprint-scene-program
         scene-program-with-fingerprints
         scene-program-first-changed-index)

(struct scene-program-fingerprint
  (source-path source-digest ambient-digest block-digests asset-digests)
  #:transparent)

;; Returns the common file recorded for a macro-authored program, or #f when
;; the program was constructed manually.  Manual programs remain compilable;
;; they simply cannot claim automatic source-equivalent reuse.
(define (scene-program-source-path program)
  (unless (scene-program? program)
    (raise-argument-error 'scene-program-source-path "scene-program?" program))
  (define locations
    (filter values
            (map scene-block-spec-source-location (scene-program-blocks program))))
  (and (pair? locations)
       (let ([source (source-location-source (car locations))])
         (and (path-string? source)
              (andmap (lambda (location)
                        (equal? source (source-location-source location)))
                      locations)
              (simplify-path (path->complete-path source))))))

;; Reads exactly once, then fingerprints every declared block span plus the
;; source around all spans.  Positions from syntax objects are one-based byte
;; positions; a malformed or out-of-range location is deliberately treated as
;; an error instead of silently enabling unsafe reuse.
(define (fingerprint-scene-program program #:source-path [requested-path #f])
  (unless (scene-program? program)
    (raise-argument-error 'fingerprint-scene-program "scene-program?" program))
  (unless (or (not requested-path) (path-string? requested-path))
    (raise-argument-error 'fingerprint-scene-program "(or/c #f path-string?)"
                          requested-path))
  (define source-path
    (simplify-path
     (path->complete-path (or requested-path
                              (scene-program-source-path program)
                              (raise-arguments-error
                               'fingerprint-scene-program
                               "a macro-recorded source path or #:source-path"
                               "program" program)))))
  (unless (file-exists? source-path)
    (raise-arguments-error 'fingerprint-scene-program "existing source file"
                           "source-path" source-path))
  (define bytes (file->bytes source-path))
  (define spans
    (for/list ([block (in-list (scene-program-blocks program))])
      (define location (scene-block-spec-source-location block))
      (unless (source-location? location)
        (raise-arguments-error
         'fingerprint-scene-program
         "source locations for all blocks"
         "block" (scene-block-spec-id block)))
      (define start (sub1 (source-location-position location)))
      (define end (+ start (source-location-span location)))
      (unless (and (exact-nonnegative-integer? start)
                   (exact-nonnegative-integer? end)
                   (<= start end (bytes-length bytes)))
        (raise-arguments-error
         'fingerprint-scene-program
         "a source span inside the loaded source file"
         "block" (scene-block-spec-id block)
         "position" (source-location-position location)
         "span" (source-location-span location)
         "source-size" (bytes-length bytes)))
      (list start end block)))
  (define sorted-spans
    (sort spans < #:key car))
  (check-disjoint-spans! sorted-spans source-path)
  (define block-digests
    (for/list ([entry (in-list spans)])
      (define start (first entry))
      (define end (second entry))
      (sha1-bytes (subbytes bytes start end))))
  (define ambient-bytes
    (let loop ([remaining sorted-spans] [position 0] [pieces '()])
      (cond
        [(null? remaining) (apply bytes-append (reverse (cons (subbytes bytes position)
                                                                pieces)))]
        [else
         (define start (first (car remaining)))
         (define end (second (car remaining)))
         (loop (cdr remaining) end (cons (subbytes bytes position start) pieces))])))
  (define asset-digests
    (for/list ([block (in-list (scene-program-blocks program))])
      (for/list ([asset (in-list (scene-block-spec-assets block))])
        (fingerprint-asset asset source-path))))
  (scene-program-fingerprint source-path
                             (sha1-bytes bytes)
                             (sha1-bytes ambient-bytes)
                             block-digests
                             asset-digests))

;; Adds a stable runtime fingerprint to each block.  The fingerprint includes
;; both its source slice and its declared assets/version, so EH's generic
;; incremental compiler needs only to compare normal immutable declarations.
(define (scene-program-with-fingerprints program fingerprint)
  (unless (scene-program? program)
    (raise-argument-error 'scene-program-with-fingerprints "scene-program?" program))
  (unless (scene-program-fingerprint? fingerprint)
    (raise-argument-error 'scene-program-with-fingerprints
                          "scene-program-fingerprint?" fingerprint))
  (define blocks (scene-program-blocks program))
  (define digests (scene-program-fingerprint-block-digests fingerprint))
  (define assets (scene-program-fingerprint-asset-digests fingerprint))
  (unless (and (= (length blocks) (length digests))
               (= (length blocks) (length assets)))
    (raise-arguments-error 'scene-program-with-fingerprints
                           "fingerprint for each program block"
                           "block-count" (length blocks)))
  (make-scene-program
   (scene-program-id program)
   (scene-program-initial-builder program)
   (for/list ([block (in-list blocks)]
              [digest (in-list digests)]
              [asset-digest (in-list assets)])
     (struct-copy scene-block-spec block
                  [source-fingerprint
                   (list digest asset-digest (scene-block-spec-version block))]))))

;; Returns the earliest source-level divergence. #f means that the program
;; source and declared assets are identical.  An ambient change necessarily
;; returns zero: code outside a block can affect every builder.
(define (scene-program-first-changed-index old new)
  (unless (scene-program-fingerprint? old)
    (raise-argument-error 'scene-program-first-changed-index
                          "scene-program-fingerprint?" old))
  (unless (scene-program-fingerprint? new)
    (raise-argument-error 'scene-program-first-changed-index
                          "scene-program-fingerprint?" new))
  (cond
    [(not (equal? (scene-program-fingerprint-ambient-digest old)
                  (scene-program-fingerprint-ambient-digest new)))
     0]
    [else
     (define old-blocks (scene-program-fingerprint-block-digests old))
     (define new-blocks (scene-program-fingerprint-block-digests new))
     (define old-assets (scene-program-fingerprint-asset-digests old))
     (define new-assets (scene-program-fingerprint-asset-digests new))
     (let loop ([index 0]
                [remaining-old old-blocks]
                [remaining-new new-blocks]
                [remaining-old-assets old-assets]
                [remaining-new-assets new-assets])
       (cond
         [(and (null? remaining-old) (null? remaining-new)) #f]
         [(or (null? remaining-old) (null? remaining-new)) index]
         [(and (equal? (car remaining-old) (car remaining-new))
               (equal? (car remaining-old-assets) (car remaining-new-assets)))
          (loop (add1 index)
                (cdr remaining-old) (cdr remaining-new)
                (cdr remaining-old-assets) (cdr remaining-new-assets))]
         [else index]))]))

(define (fingerprint-asset asset source-path)
  (define path
    (simplify-path
     (path->complete-path asset (or (path-only source-path) (current-directory)))))
  (cond
    [(file-exists? path) (list path (sha1-bytes (file->bytes path)))]
    [else (list path 'missing)]))

(define (check-disjoint-spans! spans source-path)
  (let loop ([previous-end 0] [remaining spans])
    (unless (null? remaining)
      (define entry (car remaining))
      (when (< (first entry) previous-end)
        (raise-arguments-error
         'fingerprint-scene-program
         "non-overlapping source block spans"
         "source-path" source-path
         "block" (scene-block-spec-id (third entry))))
      (loop (second entry) (cdr remaining)))))
