#lang racket/base
;; Source declarations only. Requiring this catalogue neither samples nor renders.
(provide three-d-strip-specs three-d-example-files)
(define three-d-example-files
  '("first-spatial-picture.rkt" "spatial-motion.rkt" "spatial-slides.rkt"))
;; key, source module, exported value, kind, exact sample times
(define three-d-strip-specs
  '(("first-picture" "first-spatial-picture.rkt" still scene (0))
    ("object-motion" "spatial-motion.rkt" object-motion scene (0 1/2 1 3/2 2))
    ("object-translation" "spatial-motion.rkt" translated-object scene (0 1 2))
    ("camera-motion" "spatial-motion.rkt" camera-motion scene (0 1/2 1 3/2 2))
    ("panel-motion" "spatial-motion.rkt" panel-motion scene (0 1 2))
    ("lesson" "spatial-motion.rkt" lesson scene (0 3/2 3 9/2 6))
    ("captioned-lesson" "spatial-slides.rkt" captioned-lesson scene (0 1 2 5 8))
    ("slide-lesson" "spatial-slides.rkt" film storyboard (0 1 4 7 9))))
