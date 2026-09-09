#lang racket/base

;;;
;;; Corrective composition-module boundary tests
;;;

(require racket/file
         racket/runtime-path
         rackunit
         "../private/composition-model.rkt"
         "../private/composition-conflict.rkt"
         "../private/composition-schedule.rkt"
         "../private/composition-lifecycle.rkt")

(define-runtime-path composition-model-source "../private/composition-model.rkt")
(define-runtime-path composition-conflict-source "../private/composition-conflict.rkt")
(define-runtime-path composition-schedule-source "../private/composition-schedule.rkt")
(define-runtime-path composition-lifecycle-source "../private/composition-lifecycle.rkt")
(define-runtime-path animation-source "../private/animation.rkt")

(module+ test
  ;; Requiring the pure model is enough to construct values; it has no scene
  ;; compiler dependency and therefore cannot recreate the old module cycle.
  (check-true
   (succession-animation-request?
    (composition-succession '(first second))))
  (check-false
   (regexp-match? #px"\\(require[^)]*scene[.]rkt"
                  (file->string composition-model-source)))
  (check-equal? (composition-direct-child-span 'plain-child) 1)
  (check-false
   (regexp-match? #px"\\(require[^)]*scene[.]rkt"
                  (file->string composition-schedule-source)))
  (check-equal?
   (request-effects-first-write-conflict
    (request-effects '() (list (cons 'target 'opacity)) '() '() '())
    (request-effects '() (list (cons 'target 'opacity)) '() '() '()))
   '(target . opacity))
  (check-false
   (regexp-match? #px"\\(require[^)]*scene[.]rkt"
                  (file->string composition-conflict-source)))
  (check-true
   (lifecycle-effect-valid-presence?
    (lifecycle-effect 'target 'present 'present #f #t)
    #t))
  (check-false
   (regexp-match? #px"\\(require[^)]*scene[.]rkt"
                  (file->string composition-lifecycle-source)))

  ;; Effects construct composition values through ordinary imports. The only
  ;; remaining dynamic import in animation.rkt is the renderer-layout boundary,
  ;; never a lazy import of scene.rkt for composition constructors.
  (define animation-text (file->string animation-source))
  (check-false (regexp-match? #rx"scene-module" animation-text)))
