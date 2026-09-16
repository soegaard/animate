#lang racket/base

;; Effectful, browsable gallery output built on the existing Pict and project
;; entry points. No gallery-specific movie renderer or worker pool is introduced.
(require racket/class racket/file racket/list racket/path racket/string
         file/sha1 file/zip json
         (only-in pict pict->bitmap)
         "../../main.rkt" "../../gallery.rkt" "../../pict.rkt" "../../render.rkt"
         "../../scene.rkt" "../../project.rkt"
         "../../../project.rkt" "../../../render.rkt"
         "../project-artifacts.rkt" "../preparation-session.rkt" "times.rkt")
(provide render-slide-gallery!)
(define (html text)
  (for/fold ([text (format "~a" text)]) ([p (in-list '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;") ("\"" . "&quot;")))])
    (string-replace text (car p) (cdr p))))
(define (pixels bm)
  (define result (make-bytes (* 4 (send bm get-width) (send bm get-height))))
  (send bm get-argb-pixels 0 0 (send bm get-width) (send bm get-height) result) result)
(define (save-picture! path thunk repeat)
  (define reference #f)
  (for ([i (in-range repeat)])
    (define bm (pict->bitmap (thunk)))
    (define current (pixels bm))
    (cond [reference (unless (bytes=? reference current) (error 'gallery "nonrepeatable pixels: ~a" path))]
          [else (set! reference current)
                (unless (send bm save-file path 'png) (error 'gallery "cannot write: ~a" path))]))
  (call-with-input-file path sha1))
(define (source-text id implementation-source theme fmt motion)
  (format "#lang racket/base\n(require animate/slides animate/slides/gallery\n         (only-in animate/slides/~a))\n(provide film)\n(define film\n  (make-slide-gallery #:entries '(~s) #:theme ~a #:format ~a #:motion '~a))\n"
          (regexp-replace #rx"[.]rkt$" implementation-source "")
          id (if (eq? theme 'dark) 'lecture-dark 'lecture-light)
          (if (eq? fmt 'square) 'square-format fmt) motion))
(define (write-index! path records theme fmt motion)
  (call-with-output-file path #:exists 'error
    (lambda (out)
      (display "<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Animate slide gallery</title><style>body{font:16px/1.5 system-ui,sans-serif;margin:0;background:#f5f6f8;color:#202936}header,main{max-width:1100px;margin:auto;padding:2rem}header{padding-bottom:0}nav a{margin-right:1rem}article{background:white;border:1px solid #d7dde4;border-radius:12px;padding:1.4rem;margin:1.5rem 0}h1{font-size:2.4rem;line-height:1.1}h2{margin-top:2.5rem}h3{margin-top:0}pre{overflow:auto;background:#eef1f5;padding:1rem;border-radius:6px;font:14px/1.5 ui-monospace,monospace}.poster,video{max-width:100%;max-height:65vh;display:block;margin:auto}.strip{display:flex;gap:.7rem;overflow-x:auto;padding:.8rem 0}.strip figure{margin:0;flex:0 0 240px}.strip img{width:240px;height:160px;object-fit:contain;background:#e9edf2}.strip figcaption{font-size:.8rem}.meta{color:#586678;font-size:.9rem}.error{background:#fff1ed;color:#8c2713;padding:1rem}a{color:#086b9c}code{overflow-wrap:anywhere}details{margin-top:1rem}</style>" out)
      (fprintf out "<header><h1>Animate slide gallery</h1><p>Layouts, transitions, and native mathematical content.</p><p class='meta'>Theme: ~a · Format: ~a · Motion: ~a</p><nav><a href='#layouts'>Layouts</a><a href='#transitions'>Transitions</a><a href='#integration'>Integration</a><a href='manifest.json'>Manifest</a></nav></header><main>"
               (html theme) (html fmt) (html motion))
      (for ([category (in-list '(layouts transitions integration))])
        (define group (filter (lambda (r) (equal? (hash-ref r 'category) (symbol->string category))) records))
        (unless (null? group)
          (fprintf out "<h2 id='~a'>~a</h2>" category (string-titlecase (symbol->string category)))
          (for ([r (in-list group)])
            (fprintf out "<article id='~a'><h3>~a</h3><p>~a</p><p class='meta'><code>~a</code> · Source: <code>~a</code></p>"
                     (html (hash-ref r 'id)) (html (hash-ref r 'title)) (html (hash-ref r 'description))
                     (html (hash-ref r 'id)) (html (hash-ref r 'implementation-source)))
            (cond
              [(hash-ref r 'error #f) (fprintf out "<p class='error'>~a</p>" (html (hash-ref r 'error)))]
              [else
               (fprintf out "<p class='meta'>~a seconds · ~a</p>" (hash-ref r 'duration) (html (hash-ref r 'mode)))
               (if (hash-ref r 'video #f)
                   (fprintf out "<video controls preload='metadata' poster='~a' src='~a'></video>" (html (hash-ref r 'poster)) (html (hash-ref r 'video)))
                   (fprintf out "<img class='poster' alt='~a' src='~a'>" (html (hash-ref r 'title)) (html (hash-ref r 'poster))))
               (display "<div class='strip'>" out)
               (for ([s (in-list (hash-ref r 'samples))])
                 (fprintf out "<figure><a href='~a'><img alt='Frame at ~a seconds' src='~a'></a><figcaption>t = ~a s</figcaption></figure>"
                          (html (hash-ref s 'path)) (hash-ref s 'time) (html (hash-ref s 'path)) (hash-ref s 'time)))
               (display "</div>" out)])
            (fprintf out "<details><summary>Authoring example</summary><pre>~a</pre><p><a href='~a'>Reusable storyboard source</a></p></details></article>"
                     (html (hash-ref r 'example)) (html (hash-ref r 'source))))))
      (display "<p class='meta'>Static previews are visual-only. Draft narration is silent; optional videos retain the authored subtitle track. Geometry uses parent-prepared data and the shared worker pool. The manifest records actual worker counts.</p></main></html>" out))))

(define (render-slide-gallery! selected output #:theme [theme-name 'light] #:format [format-name 'widescreen]
                               #:motion [motion 'normal] #:videos? [videos? #f]
                               #:workers [workers 1] #:fps [fps 30] #:width [width 960]
                               #:repeat [repeat 2] #:in-process? [in-process? #f] #:zip? [zip? #t])
  (define directory (simplify-path (path->complete-path output) #f))
  (define archive (string->path (string-append (path->string directory) ".zip")))
  (when (or (directory-exists? directory) (file-exists? directory) (and zip? (file-exists? archive)))
    (raise-user-error 'run-gallery "choose a fresh output directory and archive: ~a" directory))
  (define theme (if (eq? theme-name 'dark) lecture-dark lecture-light))
  (define fmt (case format-name [(widescreen) widescreen] [(standard) standard] [(portrait) portrait] [(square) square-format]))
  ;; H.264 yuv420p needs even dimensions. Preserve the exact rational aspect,
  ;; rather than rounding height and silently stretching a portrait viewport.
  (define ratio (/ (slide-format-width fmt) (slide-format-height fmt)))
  (define w-step (* 2 (numerator ratio)))
  (define effective-width (* w-step (max 1 (inexact->exact (ceiling (/ width w-step))))))
  (define height (/ effective-width ratio))
  (define size (list effective-width height))
  (unless (= width effective-width)
    (printf "Using ~a × ~a pixels to preserve aspect and even video dimensions.\n" effective-width height))
  (for ([name (in-list '("posters" "samples" "sources" "videos" "_work"))])
    (make-directory* (build-path directory name)))
  (define records '()) (define failures 0)
  (for ([e (in-list selected)])
    (define id (slide-gallery-entry-id e))
    (define stem (symbol->string id))
    (define source (string-append "sources/" stem ".rkt"))
    (display-to-file (source-text id (slide-gallery-entry-source e) theme-name format-name motion) (build-path directory source) #:exists 'error)
    (define base
      (hash 'id stem 'category (symbol->string (slide-gallery-entry-category e))
            'title (slide-gallery-entry-title e) 'description (slide-gallery-entry-description e)
            'requirements (map symbol->string (slide-gallery-entry-requirements e))
            'implementation-source (string-append "slides/" (slide-gallery-entry-source e))
            'example (slide-gallery-entry-example e) 'source source))
    (define record
      (with-handlers ([exn:fail? (lambda (exn)
                                  (set! failures (add1 failures))
                                  (eprintf "FAIL ~a: ~a\n" id (exn-message exn))
                                  (hash-set base 'error (exn-message exn)))])
        (call-with-preparation-session
         (lambda ()
        (define film (make-slide-gallery #:entries (list id) #:theme theme #:format fmt #:motion motion))
        (define prepared (prepare-storyboard! film))
        (define poster (string-append "posters/" stem ".png"))
        (define poster-sha
          (save-picture! (build-path directory poster)
                         (lambda () (storyboard->pict prepared #:at 'end #:size size)) repeat))
        (define samples
          (for/list ([t (in-list (gallery-sample-times prepared))] [i (in-naturals)])
            (define relative (format "samples/~a-~a.png" stem i))
            (define digest
              (save-picture! (build-path directory relative)
                             (lambda () (storyboard->pict prepared #:at t #:size size)) repeat))
            (hash 'time (exact->inexact t) 'path relative 'sha1 digest)))
        (define local? in-process?)
        (define video #f)
        (define execution #f)
        (when videos?
          (define src (if local?
                          (timeline-source (storyboard->timeline prepared #:size size))
                          (make-storyboard-source (build-path directory source) 'film)))
          (printf "~a: ~a video (requested capacity ~a).\n" id
                  (if local? "explicit in-process" "shared-project")
                  (if local? 1 workers))
          (define project
            (animate-project #:id id #:source src
              #:render (render-spec #:fps fps #:width effective-width #:height height
                                    #:workers (if local? 1 workers) #:worker-mode (if local? 'in-process 'auto)
                                    #:theme (slide-theme-colors theme) #:typography (slide-theme-typography theme))
              #:output (output-spec #:root (build-path directory "_work") #:name stem #:format 'mp4)
              #:encoder (encoder-spec #:codec 'h264)
              #:cache (cache-spec #:root (build-path directory "_work" "cache") #:policy 'off)))
          (define report (render-project! project))
          (set! execution (project-execution-report-diagnostics report))
          (printf "~a: ~a; started ~a worker(s).\n" id
                  (project-frame-execution-diagnostics-mode execution)
                  (project-frame-execution-diagnostics-workers-started execution))
          ;; `artifact-paths` is a semantic hash. The encoded target is the
          ;; documented `primary` artifact; frame paths live under other keys.
          (define movie
            (project-primary-artifact-path
             (project-execution-report-artifact-paths report)))
          (unless (and (file-exists? movie)
                       (regexp-match? #rx"[.]mp4$" (path->string (if (path? movie) movie (string->path movie)))))
            (error 'gallery "project primary artifact is not the expected MP4 for ~a: ~a" id movie))
          (set! video (string-append "videos/" stem ".mp4"))
          (copy-file movie (build-path directory video)))
        (printf "~a: ~a previews~a\n" id (length samples) (if video ", MP4 complete" ""))
        (define info
          (list (cons 'duration (exact->inexact (prepared-duration prepared)))
                (cons 'poster poster) (cons 'poster-sha1 poster-sha)
                (cons 'samples samples) (cons 'video video)
                (cons 'requested-workers (if local? 1 workers))
                (cons 'workers-started (if execution (project-frame-execution-diagnostics-workers-started execution) 0))
                (cons 'workers-completing
                      (if execution (project-frame-execution-diagnostics-workers-completing execution) #f))
                (cons 'mode (if execution
                                (symbol->string (project-frame-execution-diagnostics-mode execution))
                                "static previews"))))
        (for/fold ([result base]) ([pair (in-list info)])
          (hash-set result (car pair) (cdr pair)))))))
    (set! records (append records (list record))))
  (call-with-output-file (build-path directory "manifest.json") #:exists 'error
    (lambda (out)
      (write-json (hash 'schema "animate-slide-gallery-v1" 'racket (version) 'theme (symbol->string theme-name)
                        'format (symbol->string format-name) 'motion (symbol->string motion)
                        'width effective-width 'height height 'fps fps 'repeat repeat
                        'entries records 'errors failures) out)))
  (write-index! (build-path directory "index.html") records theme-name format-name motion)
  (when zip?
    ;; Keep temporary rendering frames out of the review archive. It contains
    ;; only the gallery, source declarations, previews, manifest, and final MP4s.
    (define paths
      (append (list (build-path directory "index.html") (build-path directory "manifest.json"))
              (append-map (lambda (name) (find-files file-exists? (build-path directory name)))
                          '("posters" "samples" "sources" "videos"))))
    (define parent (path-only directory))
    (parameterize ([current-directory parent])
      (apply zip archive (map (lambda (p) (find-relative-path parent p)) paths))))
  (printf "Gallery: ~a\nEntries: ~a; errors: ~a~a\n" (build-path directory "index.html")
          (length records) failures (if zip? (format "; archive: ~a" archive) ""))
  (if (= failures 0) 0 1))
