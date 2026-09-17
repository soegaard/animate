#lang racket/base
(require animate/project animate/slides animate/slides/project)
(provide lesson-project)

(define lesson-project
  (animate-project
   #:id 'manual-lesson
   #:source (storyboard-source "slide-lesson.rkt" 'film)
   #:render
   (render-spec #:fps 30 #:width 1280 #:height 720 #:workers 10
                #:theme (slide-theme-colors lecture-light)
                #:typography (slide-theme-typography lecture-light))
   #:output (output-spec #:root "slides-output/manual-videos" #:name "function-lesson")
   #:cache (cache-spec #:policy 'off)))
