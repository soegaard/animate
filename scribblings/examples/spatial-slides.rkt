;; doc: imports begin
#lang racket/base
(require animate animate/3d
         "first-spatial-picture.rkt" "spatial-motion.rkt")
(provide captioned-lesson)
;; doc: imports end

;; doc: labels begin
(define heading
  (plain-text "Turn the object, then move the camera"
              #:id 'heading #:center (vec2 0 10/3)
              #:font-size 9/25 #:color "navy"))

(define box-label
  (follow-projected-spatial
   (plain-text "Box" #:id 'box-label
               #:font-size 1/4 #:color "navy")
   #:view 'model
   #:target '(brick)
   #:offset (vec2 14 16)))

(define labelled-move
  (scene-play (scene-add still heading box-label)
              (move3d-to '(model brick) (vec3 1 0 0))
              #:duration 2))

(define captioned-lesson
  (make-lesson labelled-move))
;; doc: labels end

;; doc: slide-imports begin
(require animate/slides animate/slides/scene)
(provide clip film)
;; doc: slide-imports end

;; doc: slide begin
(define card
  (slide #:id 'spatial-lesson #:layout 'title+figure
    [title "Two ways to change a 3D picture"]
    [figure (scene-content lesson)]
    [body "First turn the box. Then move the camera."]))

(define clip
  (build-slide card
    (beat 'look #:duration 1)
    (beat 'play #:duration 6
      (play-content 'figure #:to 'end))
    (beat 'read #:duration 2)))

(define film
  (storyboard
    (storyboard-shot 'demonstration clip)))
;; doc: slide end
