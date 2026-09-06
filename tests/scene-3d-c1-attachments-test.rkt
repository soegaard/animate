#lang racket/base

;;; Corrective C-1: first-class renderer attachments and artifact cache reuse

(require rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../main.rkt"
         "../private/3d/frame-artifact-cache3d.rkt")

(define world
  (view3d
   (list (cube3d 2 #:id 'cube #:color "tomato"))
   #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
   #:camera (perspective-camera3d #:position (vec3 3 2 5) #:look-at origin3)))

(module+ test
  (define renderer (software-renderer3d))
  (define cache (make-frame-artifact-cache))
  (parameterize ([current-frame-artifact-cache cache])
    (define color
      (render-view3d-frame-artifact world 64 48 renderer #:attachments '(color)))
    (check-equal? (renderer3d-frame-artifact-attachments color) '(color))
    (check-false (renderer3d-frame-artifact-linear-depth-snapshot color))
    (check-equal? (frame-artifact-cache-render-count cache) 1)

    ;; A depth upgrade renders once more. Its superset then satisfies a later
    ;; colour-only consumer without depending on a mutable renderer equality key.
    (define color+depth
      (render-view3d-frame-artifact world 64 48 renderer
                                    #:attachments '(linear-depth color color)))
    (check-equal? (renderer3d-frame-artifact-attachments color+depth)
                  '(color linear-depth))
    (check-true (vector? (renderer3d-frame-artifact-linear-depth-snapshot color+depth)))
    (check-equal? (frame-artifact-cache-render-count cache) 2)
    (check-eq?
     color+depth
     (render-view3d-frame-artifact world 64 48 renderer #:attachments '(color)))
    (check-equal? (frame-artifact-cache-render-count cache) 2)

    (define with-ids
      (render-view3d-frame-artifact world 64 48 renderer
                                    #:attachments '(color linear-depth object-id)))
    (check-equal? (renderer3d-frame-artifact-attachments with-ids)
                  '(color linear-depth object-id))
    (check-true (vector? (renderer3d-frame-artifact-object-id-snapshot with-ids)))
    (check-not-false (renderer3d-frame-linear-depth-at with-ids 32 24))
    (check-exn exn:fail:contract?
               (lambda () (renderer3d-canonical-attachments '(color depth))))
    (check-exn exn:fail:contract?
               (lambda ()
                 (render-view3d-frame-artifact world 64 48 renderer
                                               #:attachments '(color normal)))))

  ;; The outer Pict compositor gathers all projected-label demands before it
  ;; draws the viewport. Two hide/fade labels therefore use one colour+depth
  ;; render, even when the viewport occurs first in drawing order.
  (define labelled-view
    (view3d (list (cube3d 2 #:id 'cube #:color "tomato"))
            #:id 'labelled-view #:width 4 #:height 3 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 3 2 5)
                                           #:look-at origin3)))
  (define label-scene
    (scene-wait
     (scene-add
      (scene-add
       (scene-add (make-scene) labelled-view)
       (follow-projected-point (plain-text "A" #:id 'label-a)
                               #:view 'labelled-view #:point (vec3 -1 0 0)
                               #:occlusion 'hide))
      (follow-projected-point (plain-text "B" #:id 'label-b)
                              #:view 'labelled-view #:point (vec3 1 0 0)
                              #:occlusion 'fade))
     1))
  (define labelled-cache (make-frame-artifact-cache))
  (parameterize ([current-frame-artifact-cache labelled-cache]
                 [current-view3d-renderer3d (software-renderer3d)])
    (scene->pict label-scene 0
                 #:camera (make-camera #:width 160 #:height 120 #:world-width 8))
    (check-equal? (frame-artifact-cache-render-count labelled-cache) 1)))
