#lang racket/base

;; Render authentic Pict/native comparisons, never mock images. One final
;; runner owns all visual probes, including optional math/geometry checkpoints.
(require racket/class racket/cmdline racket/file racket/list racket/path racket/runtime-path racket/string
         file/sha1 file/zip json
         (only-in pict pict->bitmap pict-width pict-height)
         (only-in "../main.rkt" scene-sample scene-camera-at scene-state->pict)
         "main.rkt" "pict.rkt" "scene.rkt" "render.rkt"
         "private/data.rkt" "private/sample.rkt"
         "examples/gallery.rkt" "gallery.rkt" "private/gallery/times.rkt")
(define-runtime-path examples-directory "examples")
(define (bitmap-bytes bm)
  (define bytes (make-bytes (* 4 (send bm get-width) (send bm get-height))))
  (send bm get-argb-pixels 0 0 (send bm get-width) (send bm get-height) bytes)
  bytes)
(define (escape-html text)
  (for/fold ([s text]) ([pair (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")))])
    (string-replace s (car pair) (cdr pair))))

;; Duplicate runner output to the terminal and to a transcript file.  The
;; transcript files live inside the review directory so the ZIP is a complete
;; diagnostic artifact instead of relying on terminal scrollback.
(define (make-probe-tee-port name terminal transcript)
  (make-output-port
   name always-evt
   (lambda (bytes start end _non-block? _breakable?)
     (cond
       [(= start end)
        (flush-output terminal)
        (flush-output transcript)
        0]
       [else
        (write-bytes bytes terminal start end)
        (write-bytes bytes transcript start end)
        (- end start)]))
   (lambda ()
     (flush-output terminal)
     (flush-output transcript))))

(define composition-mean-threshold 0.10)

(module+ main
  (define include-gallery? #f)
  (define repeat 2) (define include-math? #f) (define include-geometry? #f) (define make-zip? #t)
  (define output
    (command-line #:program "slides/run-probes.rkt"
      #:once-each
      [("--repeat") n "Repeat each sample to check deterministic rendering"
       (set! repeat (string->number n))
       (unless (exact-positive-integer? repeat) (raise-user-error 'repeat "expected a positive integer"))]
      [("--math") "Include actual prepared mathematical lesson" (set! include-math? #t)]
      [("--geometry") "Include actual geometry lesson" (set! include-geometry? #t)]
      [("--gallery") "Include the expanded layout/transition/integration gallery" (set! include-gallery? #t)]
      [("--no-zip") "Leave the review directory without a ZIP" (set! make-zip? #f)]
      #:args ([directory "slides-output/probes"]) directory))
  (define directory (simplify-path (path->complete-path output) #f))
  (when (or (file-exists? directory) (directory-exists? directory))
    (raise-user-error 'run-probes "choose a new output directory; refusing to mix prior probes: ~a" directory))
  (make-directory* directory)

  ;; Keep the ordinary terminal UX while making the review artifact
  ;; self-contained.  Unbuffered transcript files also retain diagnostics when
  ;; an unexpected exception aborts the runner before normal completion.
  (define terminal-out (current-output-port))
  (define terminal-err (current-error-port))
  (define stdout-transcript
    (open-output-file (build-path directory "stdout.txt") #:exists 'error))
  (define stderr-transcript
    (open-output-file (build-path directory "stderr.txt") #:exists 'error))
  (file-stream-buffer-mode stdout-transcript 'none)
  (file-stream-buffer-mode stderr-transcript 'none)
  (current-output-port
   (make-probe-tee-port 'slides-probe-stdout terminal-out stdout-transcript))
  (current-error-port
   (make-probe-tee-port 'slides-probe-stderr terminal-err stderr-transcript))

  (define records '()) (define errors '())
  (define (attempt label thunk)
    (with-handlers ([exn:fail? (lambda (e)
                               (eprintf "FAIL ~a: ~a\n" label (exn-message e))
                               (set! errors (append errors (list (hash 'probe label 'error (exn-message e))))))])
      (thunk)))
  (define (write-picture name thunk)
    (define path (build-path directory (string-append name ".png")))
    (define reference #f)
    (for ([i (in-range repeat)])
      (define bm (pict->bitmap (thunk)))
      (define current (bitmap-bytes bm))
      (if reference
          (unless (bytes=? reference current) (error 'probe "nonrepeatable sample: ~a" name))
          (begin
            (set! reference current)
            (unless (send bm save-file path 'png) (error 'probe "cannot write ~a" path)))))
    (values (path->string (file-name-from-path path)) reference (call-with-input-file path sha1)))
  (define (pair-probe label pict-thunk native-thunk #:context [context (hash)])
    (attempt label
      (lambda ()
        (define-values (pf pb ph) (write-picture (string-append label "-pict") pict-thunk))
        (define-values (nf nb nh) (write-picture (string-append label "-scene") native-thunk))
        (unless (= (bytes-length pb) (bytes-length nb)) (error 'probe "output sizes differ"))
        (define max-delta (for/fold ([m 0]) ([a (in-bytes pb)] [b (in-bytes nb)]) (max m (abs (- a b)))))
        (define mean-delta (/ (for/sum ([a (in-bytes pb)] [b (in-bytes nb)]) (abs (- a b))) (bytes-length pb)))
        (set! records (append records
          (list (for/fold ([record (hash 'probe label 'pict pf 'scene nf 'pict-sha1 ph 'scene-sha1 nh
                                     'maximum-channel-difference max-delta
                                     'mean-channel-difference (exact->inexact mean-delta))])
                         ([(key value) (in-hash context)]) (hash-set record key value)))))
        (printf "~a  max difference ~a; mean ~a\n" label max-delta (exact->inexact mean-delta))
        ;; Ordinary vector-text rasterization can differ by a pixel between the
        ;; Pict and native Scene paths.  The v0.4 portrait math review reached
        ;; about 0.077 mean channel difference for this benign case, while the
        ;; historical exact-cut composition bug was 3.057.  Keep enough margin
        ;; for rasterization without weakening the composition-level guard.
        (when (> mean-delta composition-mean-threshold)
          (error 'probe "Pict/Scene composition mismatch: mean channel difference ~a"
                 (exact->inexact mean-delta))))))
  (for* ([theme (in-list (list lecture-light lecture-dark))]
         [fmt (in-list (list widescreen standard portrait square-format))]
         [s (in-list gallery-slides)])
    (define label (format "~a-~a-~a" (slide-theme-id theme) (slide-format-id fmt) (slide-id s)))
    (attempt label
      (lambda ()
        (define prepared (prepare-slide! s #:theme theme #:format fmt))
        (define size (list (* 40 (slide-format-width fmt)) (* 40 (slide-format-height fmt))))
        (define scene (slide->scene prepared #:size size))
        (pair-probe label
          (lambda () (slide->pict prepared #:size size))
          (lambda () (scene-state->pict (scene-sample scene 0) #:camera (scene-camera-at scene 0)))))))
  ;; Silent examples also probe exact boundaries and shuffled time order.
  (for ([name (in-list (append '("hello.rkt" "function-lesson.rkt" "native-scene.rkt")
                               (if include-math? '("math-lesson.rkt") '())
                               (if include-geometry? '("geometry-lesson.rkt") '())))])
    (attempt name
      (lambda ()
        (define board (prepare-storyboard! (dynamic-require (build-path examples-directory name) 'film)))
        (define duration (prepared-duration board))
        (define boundaries
          (remove-duplicates
           (append (list 0 duration)
             (append-map
              (lambda (shot)
                (define offset (prepared-shot-start shot))
                (append (list offset)
                        (append-map (lambda (beat) (list (+ offset (prepared-beat-start beat))
                                                        (+ offset (prepared-beat-start beat) (prepared-beat-duration beat))))
                                    (prepared-clip-value-beats (prepared-shot-clip shot)))))
              (prepared-storyboard-value-shots board))) =))
        (define times
          (reverse (sort (remove-duplicates
                          (append boundaries
                                  (for/list ([t (in-list boundaries)] #:when (> t 0)) (max 0 (- t 1/60)))
                                  (for/list ([t (in-list boundaries)] #:when (< t duration)) (min duration (+ t 1/60)))) =) <)))
        (define scene (storyboard->scene board #:size '(640 360)))
        (for ([t (in-list times)] [index (in-naturals)])
          (define label (format "~a-~a" (path->string (path-replace-extension (string->path name) #"")) index))
          (pair-probe label
            (lambda () (storyboard->pict board #:at t #:size '(640 360)))
            (lambda () (scene-state->pict (scene-sample scene t) #:camera (scene-camera-at scene t))))))))
  ;; The author-facing gallery also receives paired native probes. Samples
  ;; include transition interiors, exact boundaries, neighboring frames, and
  ;; mid-action domain content, with explicit times in the manifest.
  (when include-gallery?
    (define selected
      (filter (lambda (e)
                (and (or include-math? (not (memq 'math (slide-gallery-entry-requirements e))))
                     (or include-geometry? (not (memq 'geometry (slide-gallery-entry-requirements e))))))
              slide-gallery-entries))
    (for* ([theme (in-list (list lecture-light lecture-dark))]
           [fmt (in-list (list widescreen portrait))]
           [entry (in-list selected)])
      (define id (slide-gallery-entry-id entry))
      (define prefix (format "gallery-~a-~a-~a" (slide-theme-id theme) (slide-format-id fmt) id))
      (attempt prefix
        (lambda ()
          (define board (prepare-storyboard! (make-slide-gallery #:entries (list id) #:theme theme #:format fmt)))
          (define size (list (* 40 (slide-format-width fmt)) (* 40 (slide-format-height fmt))))
          (define scene (storyboard->scene board #:size size))
          (for ([time (in-list (reverse (gallery-review-times board)))] [index (in-naturals)])
            (pair-probe (format "~a-~a" prefix index)
              (lambda () (storyboard->pict board #:at time #:size size))
              (lambda () (scene-state->pict (scene-sample scene time) #:camera (scene-camera-at scene time)))
              #:context (hash 'time (exact->inexact time) 'entry (symbol->string id)
                              'category (symbol->string (slide-gallery-entry-category entry))
                              'theme (symbol->string (slide-theme-id theme))
                              'format (symbol->string (slide-format-id fmt)))))))))
  (call-with-output-file (build-path directory "manifest.json") #:exists 'error
    (lambda (out)
      (write-json
       (hash 'schema "animate-slides-probes-v3"
             'racket (version)
             'repeat repeat
             'composition-mean-threshold composition-mean-threshold
             'stdout "stdout.txt"
             'stderr "stderr.txt"
             'comparisons records
             'errors errors)
       out)))
  (call-with-output-file (build-path directory "index.html") #:exists 'error
    (lambda (out)
      (display "<!doctype html><meta charset='utf-8'><title>Themeable layouts review</title><style>body{font:16px system-ui;margin:2em;max-width:1400px}article{margin:2em 0;border-top:1px solid #ccc;padding-top:1em}.pair{display:flex;gap:1em;align-items:start}.pair img{width:48%;height:auto}code{font-size:14px}</style><h1>Themeable layouts review</h1><p>Left: slide-&gt;pict. Right: native Scene. See manifest.json for exact comparison and repeatability results.</p><p>Runner transcripts: <a href='stdout.txt'>stdout.txt</a> · <a href='stderr.txt'>stderr.txt</a>.</p>" out)
      (for ([entry (in-list records)])
        (fprintf out "<article><h2>~a</h2><p>Maximum channel difference: ~a; mean: ~a</p><div class='pair'><img src='~a'><img src='~a'></div></article>"
                 (escape-html (hash-ref entry 'probe)) (hash-ref entry 'maximum-channel-difference)
                 (hash-ref entry 'mean-channel-difference) (hash-ref entry 'pict) (hash-ref entry 'scene)))
      (for ([entry (in-list errors)]) (fprintf out "<pre>~a: ~a</pre>" (escape-html (hash-ref entry 'probe)) (escape-html (hash-ref entry 'error))))))
  ;; Print the terminal summary before zipping, then flush both tee ports so the
  ;; archive contains the complete stdout/stderr transcript including summary.
  (define archive
    (and make-zip?
         (string->path (string-append (path->string directory) ".zip"))))
  (when (and archive (file-exists? archive))
    (raise-user-error 'run-probes "archive already exists: ~a" archive))
  (printf "Comparisons: ~a; errors: ~a; review: ~a\n" (length records) (length errors) directory)
  (when archive (printf "Review archive: ~a\n" archive))
  (flush-output (current-output-port))
  (flush-output (current-error-port))
  (when archive
    (parameterize ([current-directory (path-only directory)])
      (zip archive (file-name-from-path directory))))
  (exit (if (null? errors) 0 1)))
