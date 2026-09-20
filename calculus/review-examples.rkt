#lang racket/base

;;;
;;; Calculus Sparse Visual Review Runner
;;;

;; Produces inspectable, full-resolution PNG stills from the same immutable
;; preparation path used by ordinary calculus picts and scenes.  It deliberately
;; does not invent a calculus movie API: worker and movie policy remain owned
;; by animate/project, while this runner records sparse semantic evidence.


;;;
;;; Imports and Public Entry Point
;;;

(require racket/cmdline
         racket/class
         racket/file
         racket/format
         racket/list
         racket/path
         racket/string
         racket/system
         (prefix-in pict: pict)
         (only-in "private/core.rkt"
                  calculus-plan-events
                  calculus-plan-duration
                  c-event-start
                  c-event-end)
         (only-in "tests/guide-lessons-test.rkt"
                  guide-reading-square
                  guide-secant-to-tangent
                  guide-build-derivative
                  guide-limit-not-value
                  guide-sums-and-accumulation
                  guide-component-example)
         "render.rkt")

(provide run-calculus-review!
         calculus-review-fixture-ids)


;;;
;;; Immutable Review Registry
;;;

;; calculus-review-fixture : symbol? string? calculus-lesson? -> record
;;   Names a complete Guide lesson and the human-facing concern its sparse
;;   captures are intended to make inspectable.
(struct calculus-review-fixture (id note lesson) #:transparent)

;; calculus-review-row : symbol? symbol? real? path? -> record
;;   Describes one committed raster artifact.  Keeping the semantic time here
;;   makes the bundle useful without encoding time into a fragile file name.
(struct calculus-review-row (fixture profile time path) #:transparent)

(define calculus-review-fixtures
  (list
   (calculus-review-fixture
    'reading-square
    "Graph reading, guided input/output motion, and negative-input scan."
    guide-reading-square)
   (calculus-review-fixture
    'secant-to-tangent
    "Chord/secant replacement, finite approach, and settled tangent."
    guide-secant-to-tangent)
   (calculus-review-fixture
    'build-derivative
    "Shared input, derivative trace, and final derivative graph."
    guide-build-derivative)
   (calculus-review-fixture
    'limit-not-value
    "Isolated function value, punctured approaches, and epsilon-delta bands."
    guide-limit-not-value)
   (calculus-review-fixture
    'sums-and-accumulation
    "Refinement commits, signed region, trace, and accumulation tangent."
    guide-sums-and-accumulation)
   (calculus-review-fixture
    'component-example
    "Expanded component exposition, cleanup, and a finite secant study."
    guide-component-example)))

;; calculus-review-fixture-ids : -> (listof symbol?)
;;   Lists the stable selection names without preparing native output.
(define (calculus-review-fixture-ids)
  (map calculus-review-fixture-id calculus-review-fixtures))


;;;
;;; Selection and Sampling
;;;

;; resolve-profile : symbol? -> calculus-profile?
;;   Keeps the three documented review profiles in one deterministic mapping.
(define (resolve-profile profile-id)
  (case profile-id
    [(light) classroom-light-profile]
    [(dark) classroom-dark-profile]
    [(textbook) textbook-profile]
    [else
     (raise-arguments-error
      'run-calculus-review!
      "one of the documented review profile names"
      "profile" profile-id)]))

;; select-review-fixtures : (listof symbol?) -> (listof calculus-review-fixture?)
;;   Preserves the registry order so filenames and review sheets do not depend
;;   on command-line selection order.
(define (select-review-fixtures requested-ids)
  (unless (and (list? requested-ids) (andmap symbol? requested-ids))
    (raise-argument-error 'run-calculus-review! "(listof symbol?)" requested-ids))
  (define known (calculus-review-fixture-ids))
  (for ([fixture-id (in-list requested-ids)])
    (unless (member fixture-id known)
      (raise-arguments-error
       'run-calculus-review!
       "a registered calculus review fixture"
       "fixture" fixture-id
       "known-fixtures" known)))
  (filter (lambda (fixture)
            (member (calculus-review-fixture-id fixture) requested-ids))
          calculus-review-fixtures))

;; review-times : calculus-plan? -> (listof nonnegative-real?)
;;   Chooses every action's start, midpoint, and end, plus the final duration.
;;   These semantic times expose continuous transitions without making a full
;;   movie or treating a contact sheet as evidence of a transition by itself.
(define (review-times plan)
  (define event-times
    (append-map
     (lambda (event)
       (define start (c-event-start event))
       (define end (c-event-end event))
       (list start (/ (+ start end) 2) end))
     (calculus-plan-events plan)))
  (sort (remove-duplicates (append (list 0)
                                   event-times
                                   (list (calculus-plan-duration plan))))
        <))


;;;
;;; Native Files and Bundle Metadata
;;;

;; save-pict-png! : pict? path? -> void?
;;   Forces one delayed native Pict into one owned PNG file and verifies that
;;   the drawing backend reported a successful atomic bitmap write.
(define (save-pict-png! picture path)
  (define image (pict:pict->bitmap picture 'aligned))
  (unless (send image save-file path 'png)
    (raise-arguments-error
     'run-calculus-review!
     "a writable PNG destination"
     "path" path)))

;; chunks : list? exact-positive-integer? -> (listof list?)
;;   Splits a review sequence without retaining a complete contact sheet's
;;   pixel buffer until the current page is assembled.
(define (chunks values size)
  (cond [(null? values) '()]
        [else (cons (take values (min size (length values)))
                    (chunks (drop values (min size (length values))) size))]))

;; contact-sheet-picture : (listof calculus-review-row?) -> pict?
;;   Builds an explicitly labeled inspection sheet from already committed PNGs.
(define (contact-sheet-picture rows)
  (define thumbnail-width 280)
  (define (cell row)
    (define source (pict:bitmap (calculus-review-row-path row)))
    (define scale-factor (/ thumbnail-width (max 1 (pict:pict-width source))))
    (pict:vc-append
     5
     (pict:scale source scale-factor)
     (pict:text
      (format "~a  t=~a"
              (calculus-review-row-fixture row)
              (calculus-review-row-time row)))))
  (define rows-of-cells (chunks rows 3))
  (apply pict:vc-append
         14
         (for/list ([sheet-row (in-list rows-of-cells)])
           (apply pict:hc-append 14 (map cell sheet-row)))))

;; write-contact-sheets! : path? symbol? (listof calculus-review-row?) -> (listof path?)
;;   Writes paginated visual overviews.  The original full-resolution stills
;;   remain the source of truth and are linked by the HTML index.
(define (write-contact-sheets! profile-directory profile-id rows)
  (for/list ([page-rows (in-list (chunks rows 12))]
             [page-index (in-naturals 1)])
    (define path
      (build-path profile-directory
                  (format "contact-sheet-~a-~a.png"
                          profile-id
                          (~r page-index #:min-width 3 #:pad-string "0"))))
    (save-pict-png! (contact-sheet-picture page-rows) path)
    path))

;; html-escape : string? -> string?
;;   Escapes only manifest-originated text before it becomes review index HTML.
(define (html-escape text)
  (regexp-replace*
   #px">"
   (regexp-replace*
    #px"<"
    (regexp-replace* #px"&" text "&amp;")
    "&lt;")
   "&gt;"))

;; relative-name : path? path? -> string?
;;   Uses the path relative to the selected bundle root as the portable HTML
;;   link and manifest name, never an author-machine absolute path.
(define (relative-name root path)
  (path->string (find-relative-path root path)))

;; write-review-index! : path? (listof calculus-review-row?) (listof path?) (listof path?) -> void?
;;   Writes a deliberately plain, local, self-contained index for review.
(define (write-review-index! root rows sheets clips)
  (call-with-output-file
   (build-path root "index.html")
   #:exists 'error
   (lambda (output)
     (display "<!doctype html><meta charset=\"utf-8\"><title>Calculus review</title>\n" output)
     (display "<h1>Calculus sparse visual review</h1>\n" output)
     (display "<p>Inspect full-resolution stills; contact sheets are navigation only.</p>\n" output)
     (when (pair? sheets)
       (display "<h2>Contact sheets</h2><ul>\n" output)
       (for ([sheet (in-list sheets)])
         (define name (html-escape (relative-name root sheet)))
         (fprintf output "<li><a href=\"~a\">~a</a></li>\n" name name))
       (display "</ul>\n" output))
     (when (pair? clips)
       (display "<h2>Transition clips</h2><ul>\n" output)
       (for ([clip (in-list clips)])
         (define name (html-escape (relative-name root clip)))
         (fprintf output "<li><a href=\"~a\">~a</a></li>\n" name name))
       (display "</ul>\n" output))
     (display "<h2>Full-resolution stills</h2><ul>\n" output)
     (for ([row (in-list rows)])
       (define name (html-escape (relative-name root (calculus-review-row-path row))))
       (fprintf output "<li><a href=\"~a\">~a / ~a / t=~a</a></li>\n"
                name
                (calculus-review-row-profile row)
                (calculus-review-row-fixture row)
                (calculus-review-row-time row)))
     (display "</ul>\n" output))))

;; write-review-manifest! : path? ... -> void?
;;   Records only stable development evidence, not private prepared structs or
;;   executable provider closures.  The manifest is an audit artifact, not a
;;   new public serialization format.
(define (write-review-manifest! root width height requested-workers rows sheets clips)
  (call-with-output-file
   (build-path root "manifest.rktd")
   #:exists 'error
   (lambda (output)
     (write
      (hasheq
       'format 'animate-calculus-sparse-review-v1
       'racket-version (version)
       'width width
       'height height
       'requested-worker-capacity requested-workers
       'fixtures (calculus-review-fixture-ids)
       'stills
       (for/list ([row (in-list rows)])
         (hasheq 'fixture (calculus-review-row-fixture row)
                 'profile (calculus-review-row-profile row)
                 'time (calculus-review-row-time row)
                 'path (relative-name root (calculus-review-row-path row))))
       'contact-sheets
       (for/list ([sheet (in-list sheets)]) (relative-name root sheet))
       'transition-clips
       (for/list ([clip (in-list clips)]) (relative-name root clip)))
      output)
     (newline output))))

;; review-clip-frame-times : calculus-plan? exact-positive-integer? -> (listof real?)
;;   Samples an entire lesson at a fixed review cadence, including the exact
;;   settled endpoint.  It is independent of previous sparse still requests.
(define (review-clip-frame-times plan frames-per-second)
  (define duration (calculus-plan-duration plan))
  (define interval-count (max 1 (inexact->exact (ceiling (* duration frames-per-second)))))
  (for/list ([frame-index (in-range (add1 interval-count))])
    (* duration (/ frame-index interval-count))))

;; write-transition-clip! : prepared-calculus-lesson? ... -> path?
;;   Renders one short, self-contained MP4 through an available ffmpeg encoder.
;;   Temporary numbered PNGs are owned by the clip directory and removed after
;;   a successful encode, leaving the clip plus the sparse review evidence.
(define (write-transition-clip! prepared fixture-id profile-directory frames-per-second)
  (define ffmpeg (find-executable-path "ffmpeg"))
  (unless ffmpeg
    (raise-user-error 'run-calculus-review!
                      "--clips requires an ffmpeg executable on PATH"))
  (define clip-directory (build-path profile-directory "clips"))
  (define frame-directory
    (build-path clip-directory (format ".~a-frames" fixture-id)))
  (define clip-path
    (build-path clip-directory (format "~a-transition.mp4" fixture-id)))
  (make-directory* frame-directory)
  (dynamic-wind
   void
   (lambda ()
     (for ([time (in-list (review-clip-frame-times (prepared-lesson-plan prepared)
                                                    frames-per-second))]
           [index (in-naturals 1)])
       (save-pict-png!
        (prepared-lesson->pict prepared #:at time)
        (build-path frame-directory
                    (format "frame-~a.png"
                            (~r index #:min-width 3 #:pad-string "0")))))
     (unless (system* ffmpeg
                      "-y" "-hide_banner" "-loglevel" "error"
                      "-framerate" (number->string frames-per-second)
                      "-start_number" "1"
                      "-i" (path->string (build-path frame-directory "frame-%03d.png"))
                      "-c:v" "libx264" "-pix_fmt" "yuv420p"
                      (path->string clip-path))
       (raise-user-error 'run-calculus-review!
                         "ffmpeg could not encode transition clip ~a"
                         fixture-id))
     clip-path)
   (lambda ()
     (when (directory-exists? frame-directory)
       (delete-directory/files frame-directory)))))


;;;
;;; Runner and Command Line
;;;

;; run-calculus-review! : keyword-options -> (listof calculus-review-row?)
;;   Prepares each selected Guide lesson once per standard profile, then writes
;;   sparse transition stills and an inspectable local bundle.  Optional clips
;;   sample the same prepared lesson at a fixed cadence. `#:workers` is recorded
;;   alongside the artifacts because process execution is certified by the
;;   separate project-rendering gate; this direct review path never sends a
;;   native Pict closure to a worker.
(define (run-calculus-review!
         #:fixtures [fixture-ids (calculus-review-fixture-ids)]
         #:profiles [profile-ids '(light dark textbook)]
         #:width [width 1280]
         #:height [height 720]
         #:workers [workers 10]
         #:contact-sheets? [contact-sheets? #t]
         #:clips? [clips? #f]
         #:clip-fps [clip-fps 8]
         #:output [output-root "calculus-review"])
  (unless (and (exact-positive-integer? width)
               (exact-positive-integer? height)
               (exact-positive-integer? workers)
               (boolean? contact-sheets?)
               (boolean? clips?)
               (exact-positive-integer? clip-fps))
    (raise-arguments-error
     'run-calculus-review!
     "positive dimensions, worker capacity, and clip rate plus boolean output flags"
     "width" width "height" height "workers" workers
     "contact-sheets?" contact-sheets? "clips?" clips? "clip-fps" clip-fps))
  (unless (and (list? profile-ids) (andmap symbol? profile-ids) (pair? profile-ids))
    (raise-argument-error 'run-calculus-review! "nonempty (listof symbol?)" profile-ids))
  (define selected-fixtures (select-review-fixtures fixture-ids))
  (define root (path->complete-path output-root))
  (when (directory-exists? root)
    (raise-arguments-error
     'run-calculus-review!
     "a new output directory (existing review bundles are never replaced)"
     "output" root))
  (make-directory* root)
  (define all-rows '())
  (define all-sheets '())
  (define all-clips '())
  (for ([profile-id (in-list profile-ids)])
    (define profile (resolve-profile profile-id))
    (define profile-directory (build-path root (symbol->string profile-id)))
    (make-directory* profile-directory)
    (define profile-rows '())
    (for ([fixture (in-list selected-fixtures)])
      (define prepared
        (prepare-calculus-lesson
         (calculus-review-fixture-lesson fixture)
         #:profile profile #:width width #:height height))
      (for ([time (in-list (review-times (prepared-lesson-plan prepared)))]
            [index (in-naturals 1)])
        (define path
          (build-path
           profile-directory
           (format "~a-~a.png"
                   (calculus-review-fixture-id fixture)
                   (~r index #:min-width 3 #:pad-string "0"))))
        (save-pict-png! (prepared-lesson->pict prepared #:at time) path)
        (set! profile-rows
              (append profile-rows
                      (list (calculus-review-row
                             (calculus-review-fixture-id fixture)
                             profile-id time path)))))
      (when clips?
        (set! all-clips
              (append all-clips
                      (list (write-transition-clip!
                             prepared
                             (calculus-review-fixture-id fixture)
                             profile-directory clip-fps)))))
      )
    (define sheets
      (if contact-sheets?
          (write-contact-sheets! profile-directory profile-id profile-rows)
          '()))
    (set! all-rows (append all-rows profile-rows))
    (set! all-sheets (append all-sheets sheets)))
  (write-review-index! root all-rows all-sheets all-clips)
  (write-review-manifest! root width height workers all-rows all-sheets all-clips)
  all-rows)

;; parse-profile-list : string? -> (listof symbol?)
;;   Parses the concise `light,dark,textbook` command-line spelling exactly.
(define (parse-profile-list text)
  (define values
    (filter (lambda (value) (not (string=? value "")))
            (map string-trim (string-split text ","))))
  (unless (pair? values)
    (raise-arguments-error 'calculus/review-examples "one or more profile names" "profiles" text))
  (map string->symbol values))

;; positive-option : string? string? -> exact-positive-integer?
;;   Validates numeric command-line settings before native preparation begins.
(define (positive-option text flag)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-arguments-error 'calculus/review-examples "a positive integer" flag text))
  value)

(module+ main
  (define selected-fixtures '())
  (define selected-profiles '(light dark textbook))
  (define width 1280)
  (define height 720)
  (define workers 10)
  (define contact-sheets? #t)
  (define clips? #f)
  (define clip-fps 8)
  (define output-root "calculus-review")
  (define list? #f)
  (command-line
   #:program "calculus/review-examples.rkt"
   #:once-each
   [("--all") "Render every registered complete Guide lesson (the default)."
              (set! selected-fixtures (calculus-review-fixture-ids))]
   [("--fixture") fixture-id "Render one registered fixture; may be repeated."
                    (set! selected-fixtures
                          (append selected-fixtures (list (string->symbol fixture-id))))]
   [("--profiles") profile-list "Comma-separated light,dark,textbook profile names."
                   (set! selected-profiles (parse-profile-list profile-list))]
   [("--width") value "Output width in pixels; default 1280."
                (set! width (positive-option value "--width"))]
   [("--height") value "Output height in pixels; default 720."
                 (set! height (positive-option value "--height"))]
   [("--workers") value "Record companion process-gate worker capacity; default 10."
                  (set! workers (positive-option value "--workers"))]
   [("--no-contact-sheets") "Write full-resolution stills and index only."
                            (set! contact-sheets? #f)]
   [("--clips") "Encode a short fixed-cadence MP4 for every selected lesson/profile."
                (set! clips? #t)]
   [("--clip-fps") value "Transition-clip frame rate; default 8."
                   (set! clip-fps (positive-option value "--clip-fps"))]
   [("--output") directory "New output directory; default calculus-review."
                 (set! output-root directory)]
   [("--list") "List registered fixture ids without rendering."
               (set! list? #t)]
   #:args () (void))
  (if list?
      (for ([fixture-id (in-list (calculus-review-fixture-ids))])
        (displayln fixture-id))
      (let ([rows
             (run-calculus-review!
              #:fixtures (if (pair? selected-fixtures)
                             (remove-duplicates selected-fixtures)
                             (calculus-review-fixture-ids))
              #:profiles selected-profiles
              #:width width #:height height #:workers workers
              #:contact-sheets? contact-sheets?
              #:clips? clips? #:clip-fps clip-fps #:output output-root)])
        (printf "Wrote ~a full-resolution calculus review stills to ~a\n"
                (length rows) (path->complete-path output-root)))))
