#lang racket/base

;; Apply the three small native-integration edits after unpacking this archive
;; into the animate checkout. Validate every edit before writing any file.
(require racket/file racket/path racket/runtime-path racket/string)
(define-runtime-path checkout-root "..")
(define marker ";; Themeable layouts integration v1")
(define (replace-once text old new path)
  (define matches (regexp-match-positions* (regexp (regexp-quote old)) text))
  (unless (= (length matches) 1)
    (raise-arguments-error 'install "expected exactly one integration anchor; repository differs from the reviewed baseline"
                           "file" path "anchor" old "matches" (length matches)))
  (string-replace text old new #:all? #f))
(define specs
  (list
   (list "private/pict-adapter.rkt"
         (cons "(require racket/class"
               (string-append marker "\n(require \"prepared-pict-visual.rkt\"\n         racket/class"))
         (cons "    [(semantic-text-visual? visual)\n     ;; Do this before renderer dispatch."
               "    [(prepared-panel? visual)\n     (prepared-panel->pict
      visual camera
      (lambda (state #:camera nested-camera #:theme theme #:typography typography)
        (scene-state->pict state #:camera nested-camera #:theme theme
                          #:typography typography #:renderers renderers)))]\n    [(semantic-text-visual? visual)\n     ;; Do this before renderer dispatch."))
   (list "math/private/prepare.rkt"
         (cons "(define (prepare-math-plan! plan\n          #:camera [camera #f]"
               (string-append marker "\n(define (prepare-math-plan! plan\n          #:minimum-scale [minimum-scale 0]\n          #:foreground [foreground-override #f]\n          #:background [background-override #f]\n          #:camera [camera #f]"))
         (cons "  (define-values (foreground background) (theme-colors theme))\n  (define cam"
               "  (for ([color (in-list (list foreground-override background-override))])\n    (unless (or (not color) (and (string? color) (regexp-match? #px\"^#[0-9a-fA-F]{6}$\" color)))\n      (raise-argument-error 'prepare-math-plan! \"#f or #RRGGBB color override\" color)))\n  (define-values (default-foreground default-background) (theme-colors theme))\n  (define foreground (or foreground-override default-foreground))\n  (define background (or background-override default-background))\n  (define cam")
         (cons "  (define scale (min 1 (/ (- world-width 7/5) (max 1/10 (- xmax xmin)))))"
               "  (define scale (min 1 (/ (- world-width 7/5) (max 1/10 (- xmax xmin)))))\n  (unless (and (real? minimum-scale) (<= 0 minimum-scale 1))\n    (raise-argument-error 'prepare-math-plan! \"real in [0,1] as #:minimum-scale\" minimum-scale))\n  (when (< scale minimum-scale)\n    (raise-arguments-error 'prepare-math-plan! \"formula fitting would violate the minimum readable scale\"\n                           \"required-scale\" scale \"minimum-scale\" minimum-scale))"))
   (list "math/private/animate-adapter.rkt"
         (cons "(define (append-prepared-math-plan! initial-scene prepared"
               (string-append marker "\n(define (append-prepared-math-plan! initial-scene prepared"))
         (cons "          #:top-margin [top-margin 2] #:on-step [on-step #f])"
               "          #:top-margin [top-margin 2] #:on-step [on-step #f]\n          #:on-step-end [on-step-end #f])")
         (cons "  (when on-step (check-procedure 'append-prepared-math-plan! on-step 3))"
               "  (when on-step (check-procedure 'append-prepared-math-plan! on-step 3))\n  (when on-step-end (check-procedure 'append-prepared-math-plan! on-step-end 3))")
         (cons "        (set! scn (commit-checkpoint! scn)))\n      (set! scn (play scn '() (presentation-style-pause-between-groups style))))"
               "        (set! scn (commit-checkpoint! scn))\n        (when on-step-end (set! scn (on-step-end scn segment-index name))))\n      (set! scn (play scn '() (presentation-style-pause-between-groups style))))"))))
(provide install-themeable-layouts!)
(define (install-themeable-layouts! #:root [root checkout-root])
(define pending
  (for/list ([spec (in-list specs)])
    (define path (build-path root (car spec)))
    (define original (file->string path))
    (define installed? (string-contains? original marker))
    (list path original
          (if installed? original
              (for/fold ([text original]) ([replacement (in-list (cdr spec))])
                (replace-once text (car replacement) (cdr replacement) path))))))
(define (atomic-write path text)
  (define tmp (make-temporary-file "slides-install-~a" #f (path-only path)))
  (dynamic-wind void
                (lambda () (display-to-file text tmp #:exists 'truncate/replace)
                           (rename-file-or-directory tmp path #t))
                (lambda () (when (file-exists? tmp) (delete-file tmp)))))
(with-handlers ([exn:fail? (lambda (e)
                            (for ([entry (in-list pending)]) (atomic-write (car entry) (cadr entry)))
                            (raise e))])
  (for ([entry (in-list pending)])
    (cond [(equal? (cadr entry) (caddr entry)) (printf "Already integrated: ~a\n" (car entry))]
          [else (atomic-write (car entry) (caddr entry)) (printf "Integrated: ~a\n" (car entry))])))
(printf "Integration complete. Run racket slides/run-tests.rkt from the checkout root.\n")

)
(module+ main (install-themeable-layouts!))
