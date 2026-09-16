#lang racket/base

;;;
;;; Mathematical Gallery Review Bundles
;;;
;; Renders sparse native stills, paginated contact sheets, and inspectable timing
;; metadata. Review work stays local and does not allocate a movie worker pool.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/class send)
         (only-in racket/file make-directory* make-temporary-file delete-directory/files)
         (only-in racket/list take drop)
         (only-in racket/path path-only)
         (only-in racket/format ~r)
         (only-in racket/string string-replace)
         json file/zip
         "../../main.rkt" "../../private/native.rkt"
         "model.rkt" "render.rkt" "review-model.rkt")
(provide write-gallery-index! write-gallery-review! gallery-frame-bitmap! gallery-bitmap-bytes)

; json-time : real? -> real?
;;   Converts exact schedule times only at the JSON boundary; exact strings are also stored.
(define (json-time time) (exact->inexact time))

; entry-record : gallery-entry? -> immutable-hash?
;;   Describes a replay's source, mathematical schedule, and absolute gallery extent.
(define (entry-record entry)
  (define plate (gallery-entry-plate entry))
  (define view (gallery-entry-view entry))
  (hasheq 'plate (symbol->string (gallery-plate-id plate))
          'chapter (symbol->string (gallery-plate-chapter plate))
          'view (symbol->string (gallery-view-id view))
          'title (gallery-plate-title plate) 'variant-title (gallery-view-title view)
          'caption (gallery-view-caption view)
          'api (map symbol->string (gallery-view-api view))
          'start (json-time (gallery-entry-start entry))
          'start-exact (format "~s" (gallery-entry-start entry))
          'end (json-time (gallery-entry-end entry))
          'end-exact (format "~s" (gallery-entry-end entry))
          'mathematical-duration (json-time (plan-duration (gallery-view-plan view)))
          'source (format "math/examples/gallery/~a.rkt" (gallery-plate-chapter plate))))

; write-json-file! : path-string? any/c -> void?
;;   Writes one UTF-8 JSON evidence record to an explicitly owned destination.
(define (write-json-file! path datum)
  (call-with-output-file path #:exists 'truncate/replace (lambda (out) (write-json datum out))))

; write-gallery-index! : path-string? list? [#:fps integer?] -> void?
;;   Writes the catalogue and exact timestamps next to a rendered frame sequence.
(define (write-gallery-index! output plates #:fps [fps 30])
  (write-json-file! (build-path output "gallery-index.json")
    (hasheq 'schema "animate-math-gallery-index-v1" 'fps fps
            'duration (json-time (gallery-duration plates))
            'duration-exact (format "~s" (gallery-duration plates))
            'entries (map entry-record (gallery-entries plates)))))

; gallery-frame-bitmap! : scene? nonnegative-real? -> any/c
;;   Samples and paints through the actual native scene and Pict renderer.
(define (gallery-frame-bitmap! scn time)
  ((native 'pict 'pict->bitmap)
   ((native 'animate 'scene-state->pict)
     ((native 'animate 'scene-sample) scn time)
     #:camera ((native 'animate 'scene-camera-at) scn time))))

; gallery-bitmap-bytes : any/c -> bytes?
;;   Reads actual pixels for repeat-sampling and native-equivalence probes.
(define (gallery-bitmap-bytes bitmap)
  (define pixels (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) pixels)
  pixels)

; probe-record : gallery-probe? string? -> immutable-hash?
;;   Joins the visible frame to its phase, case, semantic step, and held checkpoint.
(define (probe-record probe file)
  (define checkpoint (gallery-probe-checkpoint probe))
  (define phase (gallery-probe-phase probe))
  (hasheq 'file file 'plate (symbol->string (gallery-plate-id (gallery-entry-plate (gallery-probe-entry probe))))
          'view (symbol->string (gallery-view-id (gallery-entry-view (gallery-probe-entry probe))))
          'kind (symbol->string (gallery-probe-kind probe))
          'time (json-time (gallery-probe-time probe)) 'time-exact (format "~s" (gallery-probe-time probe))
          'local-time (json-time (gallery-probe-local-time probe))
          'phase (and phase (symbol->string (scheduled-phase-kind phase)))
          'phase-fraction (and (gallery-probe-fraction probe) (format "~s" (gallery-probe-fraction probe)))
          'step (format "~s" (if phase (scheduled-phase-step phase) (math-checkpoint-step checkpoint)))
          'case (format "~s" (math-checkpoint-case-path checkpoint))
          'checkpoint-datum (format "~s" (math-datum (math-checkpoint-state checkpoint)))
          'checkpoint-tex (math->tex (math-checkpoint-state checkpoint))))

; html-escape : string? -> string?
;;   Escapes display strings without interpreting mathematical source as HTML.
(define (html-escape text)
  (for/fold ([s text]) ([from (in-list '("&" "<" ">" "\""))]
                       [to (in-list '("&amp;" "&lt;" "&gt;" "&quot;"))])
    (string-replace s from to)))

; contact-sheet! : path-string? list? integer? -> string?
;;   Writes one bounded six-cell native contact sheet using the already saved stills.
(define (contact-sheet! root records page)
  (define (cell record)
    (define image ((native 'pict 'bitmap) (build-path root (hash-ref record 'file))))
    (define scaled ((native 'pict 'scale) image (/ 360 ((native 'pict 'pict-width) image))))
    (define label (format "~a / ~a | ~a s | ~a"
                          (hash-ref record 'plate) (hash-ref record 'view)
                          (~r (hash-ref record 'time) #:precision '(= 2)) (hash-ref record 'kind)))
    (define caption ((native 'pict 'text) label null 10))
    ((native 'pict 'inset)
     ((native 'pict 'vl-append) 5 scaled caption) 8))
  (define cells (map cell records))
  (define first-row (take cells (min 3 (length cells))))
  (define second-row (drop cells (min 3 (length cells))))
  (define row1 (apply (native 'pict 'ht-append) 4 first-row))
  (define sheet (if (null? second-row) row1
                    ((native 'pict 'vl-append) 8 row1 (apply (native 'pict 'ht-append) 4 second-row))))
  (define file (format "sheet-~a.png" (~r page #:min-width 3 #:pad-string "0")))
  (unless (send ((native 'pict 'pict->bitmap) sheet) save-file (build-path root file) 'png)
    (raise-user-error 'gallery-review "could not save contact sheet ~a" file))
  file)

; zip-review! : path-string? path-string? -> void?
;;   Packages only the owned review directory using relative, portable archive names.
(define (zip-review! root output)
  (define zip-path (path->complete-path output))
  (make-directory* (path-only zip-path))
  (when (or (file-exists? zip-path) (directory-exists? zip-path) (link-exists? zip-path))
    (raise-user-error 'gallery-review "ZIP destination already exists: ~a" zip-path))
  (define temporary (make-temporary-file "gallery-review-~a.zip" #f (path-only zip-path)))
  (dynamic-wind void
    (lambda ()
      ;; file/zip creates its own destination, so release the reserved empty file first.
      (delete-file temporary)
      (parameterize ([current-directory root])
        (apply zip temporary (sort (directory-list root) path<?)))
      (rename-file-or-directory temporary zip-path #f))
    (lambda () (when (file-exists? temporary) (delete-file temporary)))))

; write-gallery-review! : list? path-string? [#:theme symbol?] [#:width integer?]
;   [#:height integer?] [#:show-api? boolean?] [#:dense? boolean?]
;   [#:zip (or/c #f path-string?)] -> immutable-hash?
;;   Renders native random-access stills and paginated review material without a worker pool.
(define (write-gallery-review! plates destination #:theme [theme 'light] #:width [width 1280]
                               #:height [height 720] #:show-api? [show-api? #f]
                               #:dense? [dense? #t] #:zip [zip-output #f])
  (define root (path->complete-path destination))
  (when (or (directory-exists? root) (file-exists? root) (link-exists? root))
    (raise-user-error 'gallery-review "review destination must be new: ~a" root))
  (define entries (gallery-entries plates))
  (define camera (make-gallery-camera! width height theme))
  (define preparations (prepare-gallery-views! entries camera theme))
  (define scene (build-gallery-scene! entries preparations camera #:show-api? show-api?))
  (make-directory* (build-path root "stills"))
  (define records
    (for/list ([probe (in-list (gallery-review-points entries #:dense? dense?))] [i (in-naturals)])
      (define file (format "stills/probe-~a.png" (~r i #:min-width 5 #:pad-string "0")))
      (define bitmap (gallery-frame-bitmap! scene (gallery-probe-time probe)))
      ;; Deliberately seek elsewhere and back. No earlier-frame evaluation is required.
      (gallery-frame-bitmap! scene (max 0 (- (gallery-duration plates) 1/5)))
      (unless (equal? (gallery-bitmap-bytes bitmap)
                      (gallery-bitmap-bytes (gallery-frame-bitmap! scene (gallery-probe-time probe))))
        (raise-user-error 'gallery-review "nondeterministic native pixels at ~a" (gallery-probe-time probe)))
      (unless (send bitmap save-file (build-path root file) 'png)
        (raise-user-error 'gallery-review "failed to save ~a" file))
      (probe-record probe file)))
  (define sheets
    (let loop ([remaining records] [page 1])
      (if (null? remaining) '()
        (let ([n (min 6 (length remaining))])
          (cons (contact-sheet! root (take remaining n) page)
                (loop (drop remaining n) (add1 page)))))))
  (write-gallery-index! root plates)
  (define manifest (hasheq 'schema "animate-math-gallery-review-v1" 'theme (symbol->string theme)
                           'width width 'height height 'worker-count 0
                           'native-repeat-pixel-checks (length records) 'stills records 'sheets sheets))
  (write-json-file! (build-path root "manifest.json") manifest)
  (call-with-output-file (build-path root "index.html") #:exists 'error
    (lambda (out)
      (display "<!doctype html><meta charset='utf-8'><title>Math gallery review</title><style>body{font:16px system-ui;margin:2em;background:#eee;color:#111}img{max-width:100%}table{border-collapse:collapse}td,th{padding:.4em;border:1px solid #aaa}</style><h1>Math gallery review</h1><p>Read, during, and settled frames. Step and case metadata are in manifest.json.</p>" out)
      (for ([sheet (in-list sheets)]) (fprintf out "<p><a href='~a'><img src='~a'></a></p>" sheet sheet))
      (display "<h2>Individual stills</h2><table><tr><th>Plate/view</th><th>Time</th><th>Kind</th><th>Step</th></tr>" out)
      (for ([record (in-list records)])
        (fprintf out "<tr><td><a href='~a'>~a / ~a</a></td><td>~a</td><td>~a</td><td>~a</td></tr>"
                 (hash-ref record 'file) (html-escape (hash-ref record 'plate))
                 (html-escape (hash-ref record 'view)) (hash-ref record 'time)
                 (hash-ref record 'kind) (html-escape (hash-ref record 'step))))
      (display "</table>" out)))
  (when zip-output (zip-review! root zip-output))
  manifest)
