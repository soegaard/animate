#lang racket/base

;; File/ZIP boundary, independent of the native renderer. The renderer and the
;; contact-sheet writer are callbacks so planning and failure handling can be
;; tested in a base-only Racket installation. Only managed review outputs may
;; be replaced; video frame directories and hand-added notes are not deleted.
(require racket/file racket/path racket/list racket/string racket/format
         json file/zip
         "../review-plan.rkt" "../core.rkt")
(provide (struct-out geometry-review-result) write-geometry-review-bundle!
         review-manifest-format)

(define review-manifest-format "animate-geometry-review")
(struct geometry-review-result (directory zip step-count image-count contact-sheets) #:transparent)
(define (json-caption v) (or v 'null))
(define (seconds n) (exact->inexact n))
(define (fmt n) (~r (exact->inexact n) #:precision '(= 3)))
(define (safe-leaf? s)
  (and (string? s) (regexp-match? #px"^[A-Za-z0-9][A-Za-z0-9._-]*$" s)
       (not (member s '("." "..")))))
(define (path-within? path directory)
  (define p (explode-path path)) (define d (explode-path directory))
  (and (<= (length d) (length p)) (equal? d (take p (length d)))))

(define (managed-directory? directory)
  (define marker (build-path directory "manifest.json"))
  (and (file-exists? marker) (not (link-exists? marker))
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (define m (call-with-input-file marker read-json))
         (define files (hash-ref m 'files #f))
         (and (equal? (hash-ref m 'format #f) review-manifest-format)
              (list? files) (andmap safe-leaf? files)
              (equal? (sort (map path->string (directory-list directory)) string<?)
                      (sort files string<?))
              (for/and ([f (in-list files)])
                (define p (build-path directory f))
                (and (file-exists? p) (not (link-exists? p))))))))
(define (check-destination! directory)
  (when (or (link-exists? directory) (file-exists? directory))
    (error 'geometry-review "review output must be a directory, not a file or link: ~a" directory))
  (when (and (directory-exists? directory) (pair? (directory-list directory))
             (not (managed-directory? directory)))
    (error 'geometry-review
           "refusing to replace non-review files in ~a; choose an empty/new directory (hand-added notes are preserved by refusing replacement)"
           directory)))

(define (check-png! path [width #f] [height #f])
  (unless (and (file-exists? path) (not (link-exists? path)))
    (error 'geometry-review "renderer did not create a regular PNG file: ~a" path))
  (define header (call-with-input-file path (lambda (in) (read-bytes 24 in))))
  (unless (and (bytes? header) (= (bytes-length header) 24)
               (bytes=? (subbytes header 0 8) #"\211PNG\r\n\032\n")
               (bytes=? (subbytes header 12 16) #"IHDR"))
    (error 'geometry-review "renderer produced an invalid PNG header: ~a" path))
  (define w (integer-bytes->integer header #f #t 16 20))
  (define h (integer-bytes->integer header #f #t 20 24))
  (unless (and (> w 0) (> h 0) (or (not width) (= width w)) (or (not height) (= height h)))
    (error 'geometry-review "unexpected image size ~ax~a in ~a (expected ~ax~a)" w h path width height)))

(define (step->json row)
  (define span (geometry-review-step-span row))
  (hash 'number (geometry-review-step-number row)
        'source_path (geometry-step-span-path span)
        'expanded_overview (geometry-step-span-expanded? span)
        'narration (json-caption (geometry-review-step-caption row))
        'start_seconds (seconds (geometry-step-span-start span))
        'action_start_seconds (seconds (geometry-step-span-action-start span))
        'action_end_seconds (seconds (geometry-step-span-action-end span))
        'end_seconds (seconds (geometry-step-span-end span))
        'notes (geometry-review-step-notes row)
        'actions
        (for/list ([e (in-list (geometry-step-span-events span))])
          (hash 'start_seconds (seconds (geometry-event-start e))
                'end_seconds (seconds (geometry-event-end e))
                'operations
                (for/list ([a (in-list (geometry-event-actions e))])
                  (hash 'kind (symbol->string (geometry-action-kind a))
                        'targets (map symbol->string (geometry-action-targets a))))))
        'samples
        (for/list ([s (in-list (geometry-review-step-samples row))])
          (hash 'phase (symbol->string (geometry-review-sample-phase s))
                'time_seconds (seconds (geometry-review-sample-time s))
                'file (geometry-review-sample-filename s)
                'shown_narration (json-caption (geometry-frame-narration (geometry-review-sample-frame s)))
                'note (geometry-review-sample-note s)))))

(define (sample-counts plan)
  (map (lambda (row) (length (geometry-review-step-samples row))) plan))
(define (sample-count-summary plan)
  (define counts (remove-duplicates (sort (sample-counts plan) <)))
  (cond [(null? counts) "0 images per step"]
        [(= (length counts) 1) (format "~a images per step" (car counts))]
        [else (format "~a–~a images per step" (car counts) (last counts))]))

(define (write-steps! plan directory name theme)
  (call-with-output-file (build-path directory "steps.txt")
    (lambda (out)
      (fprintf out "~a / ~a\n~a steps; ~a.\n\n" name theme (length plan) (sample-count-summary plan))
      (display "Read: unchanged pre-action state. Settled: completed post-action state, before the next step.\nMost rows include one action sample (During). Compass-circle rows instead include Pickup, Source-Attention,\nTransport, Target-Attention, and Sweep samples so the full transfer choreography can be reviewed. Expanded\noverview rows include their child steps. Synthetic helper setup/cleanup is folded into the overview rather\nthan shown as additional authored steps.\n\n" out)
      (for ([row (in-list plan)])
        (define span (geometry-review-step-span row))
        (fprintf out "STEP ~a  [source ~a]~a\n~a\n"
                 (geometry-review-step-number row)
                 (string-join (map number->string (geometry-step-span-path span)) ".")
                 (if (geometry-step-span-expanded? span) "  expanded overview" "")
                 (or (geometry-review-step-caption row) "(No new narration)"))
        (for ([note (in-list (geometry-review-step-notes row))]) (fprintf out "  ~a\n" note))
        (for ([s (in-list (geometry-review-step-samples row))])
          (fprintf out "  ~a  t=~a s\n    ~a\n" (geometry-review-sample-filename s)
                   (fmt (geometry-review-sample-time s)) (geometry-review-sample-note s)))
        (newline out))) #:exists 'error))

(define (html text)
  (for/fold ([s (format "~a" text)]) ([old (in-list '("&" "<" ">" "\"" "'"))]
                                     [new (in-list '("&amp;" "&lt;" "&gt;" "&quot;" "&#39;"))])
    (string-replace s old new)))
(define (write-index! plan directory name theme sheet-names)
  (call-with-output-file (build-path directory "index.html")
    (lambda (out)
      (define image-count (apply + (sample-counts plan)))
      (display "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Geometry review</title>\n<style>body{font:16px/1.45 system-ui,sans-serif;margin:24px;background:#f5f6f8;color:#18202a}main{max-width:1700px;margin:auto}section{margin:24px 0;padding:16px;background:white;border:1px solid #ccd2da;border-radius:6px}h2{font-size:19px;margin:0 0 6px}.frames{display:grid;gap:12px}figure{margin:0}img{width:100%;height:auto;border:1px solid #ddd}figcaption,small{color:#4b5563}a{color:#164b88}code{white-space:pre-wrap}@media(max-width:650px){.frames{grid-template-columns:1fr !important}}</style><main>\n" out)
      (fprintf out "<h1>~a / ~a</h1><p>~a steps · ~a images. Click an image for full resolution.</p>\n"
               (html name) (html theme) (length plan) image-count)
      (fprintf out "<p>Review rows contain ~a. Standard rows use read/during/settled. Compass-circle rows use read/pickup/source-attention/transport/target-attention/sweep/settled.</p>"
               (html (sample-count-summary plan)))
      (display "<p><a href=\"steps.txt\">Step captions and sample times</a> · <a href=\"manifest.json\">Manifest</a></p>" out)
      (when (pair? sheet-names)
        (display "<p>Contact sheets: " out)
        (for ([f (in-list sheet-names)] [i (in-naturals 1)])
          (fprintf out "<a href=\"~a\">~a</a> " (html f) i))
        (display "</p>" out))
      (for ([row (in-list plan)])
        (define span (geometry-review-step-span row))
        (define sample-count (length (geometry-review-step-samples row)))
        (fprintf out "<section id=\"step-~a\"><h2>Step ~a~a</h2><p>~a</p><small>Source path: ~a</small>\n"
                 (geometry-review-step-number row) (geometry-review-step-number row)
                 (if (geometry-step-span-expanded? span) " — expanded overview" "")
                 (html (or (geometry-review-step-caption row) "(No new narration)"))
                 (html (string-join (map number->string (geometry-step-span-path span)) ".")))
        (for ([note (in-list (geometry-review-step-notes row))])
          (fprintf out "<p><small>~a</small></p>" (html note)))
        (fprintf out "<div class=\"frames\" style=\"grid-template-columns:repeat(~a,minmax(0,1fr))\">" sample-count)
        (for ([s (in-list (geometry-review-step-samples row))])
          (define file (geometry-review-sample-filename s))
          (fprintf out "<figure><a href=\"~a\"><img loading=\"lazy\" src=\"~a\" alt=\"~a\"></a><figcaption>~a · ~a s</figcaption></figure>"
                   (html file) (html file) (html file) (html (geometry-review-sample-phase s))
                   (fmt (geometry-review-sample-time s))))
        (display "</div></section>\n" out))
      (display "</main></html>\n" out)) #:exists 'error))

(define (write-geometry-review-bundle! timeline plan directory
                                       #:name name #:theme [theme "light"]
                                       #:width [width 1280] #:height [height 720]
                                       #:supersample [supersample 1] #:fps [fps 30]
                                       #:captions? [captions? #t] #:expanded? [expanded? #t]
                                       #:include-cleanup? [include-cleanup? #f]
                                       #:zip [zip-path #f]
                                       #:render-sample! render-sample!
                                       #:contact-sheets! [contact-sheets! #f])
  (unless (and (geometry-timeline? timeline) (pair? plan) (andmap geometry-review-step? plan)
               (safe-leaf? name) (string? theme) (path-string? directory)
               (exact-positive-integer? width) (exact-positive-integer? height)
               (exact-positive-integer? supersample) (exact-positive-integer? fps)
               (boolean? captions?) (boolean? expanded?) (boolean? include-cleanup?)
               (procedure-arity-includes? render-sample! 2)
               (or (not contact-sheets!) (procedure-arity-includes? contact-sheets! 2))
               (or (not zip-path) (path-string? zip-path)))
    (error 'geometry-review "invalid review options or renderer callback"))
  (define dest (simplify-path (path->complete-path directory) #f))
  (define archive (and zip-path (simplify-path (path->complete-path zip-path) #f)))
  (define parent (path-only dest))
  (unless parent (error 'geometry-review "review directory needs a parent"))
  (check-destination! dest)
  (when archive
    (when (or (path-within? archive dest) (directory-exists? archive) (link-exists? archive))
      (error 'geometry-review "ZIP must be a regular file outside the review directory: ~a" archive)))
  (define samples (geometry-review-samples plan))
  (define names (map geometry-review-sample-filename samples))
  (unless (and (andmap (lambda (row) (>= (length (geometry-review-step-samples row)) 3)) plan)
               (andmap safe-leaf? names)
               (= (length names) (length (remove-duplicates names))))
    (error 'geometry-review "review plan must assign at least three unique safe filenames to each step"))
  (make-directory* parent)
  (define staging (make-temporary-file ".geometry-review-~a" 'directory parent))
  (define temporary-zip #f)
  (define backup #f)
  (define published? #f)
  (define complete? #f)
  (define sheet-names '())
  (dynamic-wind
   void
   (lambda ()
     (for ([s (in-list samples)])
       (define target (build-path staging (geometry-review-sample-filename s)))
       (render-sample! s target)
       (check-png! target (* width supersample) (* height supersample)))
     (when contact-sheets!
       (set! sheet-names (contact-sheets! plan staging))
       (unless (and (list? sheet-names) (andmap safe-leaf? sheet-names)
                    (andmap (lambda (f) (regexp-match? #px"^contact-sheet(?:-[0-9]+)?\\.png$" f)) sheet-names)
                    (= (length sheet-names) (length (remove-duplicates sheet-names))))
         (error 'geometry-review "invalid contact-sheet filenames"))
       (for ([f (in-list sheet-names)]) (check-png! (build-path staging f))))
     (write-steps! plan staging name theme)
     (write-index! plan staging name theme sheet-names)
     (define files (sort (append names sheet-names '("steps.txt" "index.html" "manifest.json")) string<?))
     (define manifest
       (hash 'format review-manifest-format 'version 1 'geometry_version "0.9.8"
             'name name 'theme theme 'width width 'height height
             'raster_width (* width supersample) 'raster_height (* height supersample)
             'reference_fps fps 'sampling "exact action times and explicit step-boundary states; not rounded to movie frames"
             'duration_seconds (seconds (geometry-timeline-duration timeline))
             'captions captions? 'expanded_steps expanded? 'include_cleanup_steps include-cleanup?
             'step_count (length plan) 'image_count (length samples)
             'contact_sheets sheet-names 'files files 'steps (map step->json plan)))
     (call-with-output-file (build-path staging "manifest.json")
       (lambda (out) (write-json manifest out) (newline out)) #:exists 'error)
     (unless (equal? (sort (map path->string (directory-list staging)) string<?) files)
       (error 'geometry-review "review output has missing or unexpected files"))
     ;; All renderers succeeded before any previous review output is touched.
     (when archive
       (make-directory* (path-only archive))
       (set! temporary-zip (make-temporary-file ".geometry-review-zip-~a" #f (path-only archive)))
       (parameterize ([current-directory staging])
         (call-with-output-file temporary-zip
           (lambda (out)
             (zip->output files out #:path-prefix name
                          #:timestamp 315532800 #:utc-timestamps? #t))
           #:exists 'truncate/replace)))
     (check-destination! dest)
     (when (directory-exists? dest)
       (set! backup (make-temporary-file ".geometry-review-backup-~a" 'directory parent))
       (delete-directory backup)
       (rename-file-or-directory dest backup #f))
     (rename-file-or-directory staging dest #f)
     (set! published? #t)
     (when archive (rename-file-or-directory temporary-zip archive #t))
     (set! complete? #t)
     (geometry-review-result dest archive (length plan) (length samples)
                             (map (lambda (f) (build-path dest f)) sheet-names)))
   (lambda ()
     (unless complete?
       (when (and published? (directory-exists? dest)) (delete-directory/files dest))
       (when (and backup (directory-exists? backup)) (rename-file-or-directory backup dest #f)))
     (when (directory-exists? staging) (delete-directory/files staging))
     (when (and temporary-zip (file-exists? temporary-zip)) (delete-file temporary-zip))
     (when (and complete? backup (directory-exists? backup)) (delete-directory/files backup)))))
