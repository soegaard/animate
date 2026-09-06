#lang racket/base

;;;
;;; SCENE-3D-E Spatial Relation Cycle and Structure Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define (template id)
  (mesh3d #:id id #:vertices (vector origin3)))

(module+ test
  ;; The cycle report uses full paths rooted in its owning view, rather than
  ;; anonymous resolver names or a partial local fragment.
  (define first
    (spatial-relation
     (template 'first)
     #:depends-on (list (spatial-visual-dependency '(second)))
     (lambda (context source)
       (spatial-relation-context-spatial-ref context '(second))
       source)))
  (define second
    (spatial-relation
     (template 'second)
     #:depends-on (list (spatial-visual-dependency '(first)))
     (lambda (context source)
       (spatial-relation-context-spatial-ref context '(first))
       source)))
  (define cyclic-scene
    (scene-add (make-scene) (view3d (list first second) #:id 'world)))
  (check-exn
   (lambda (failure)
     (and (exn:fail? failure)
          (regexp-match? #rx"spatial relation dependency cycle" (exn-message failure))
          (regexp-match? #rx"world.*first.*world.*second.*world.*first"
                         (exn-message failure))))
   (lambda ()
     (scene-state-resolved-ref (scene-sample cyclic-scene 0) 'world)))

  ;; A fixed relation owns a stable published child tree. Returning an
  ;; incompatible tree is a deterministic semantic error before rendering.
  (define fixed
    (spatial-relation
     (group3d (list (template 'stable-child)) #:id 'fixed)
     #:structure 'fixed
     (lambda (_context _source)
       (group3d (list (template 'different-child)) #:id 'fixed))))
  (check-exn
   (lambda (failure)
     (and (exn:fail? failure)
          (regexp-match? #rx"fixed spatial relation result" (exn-message failure))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-sample
       (scene-add (make-scene) (view3d (list fixed) #:id 'world))
       0)
      'world)))

  ;; Root-only relations never accidentally make temporary returned children
  ;; public targets. The error identifies the stable root and full request.
  (define root-only
    (spatial-relation
     (group3d (list (template 'template-child)) #:id 'root-only)
     (lambda (_context _source)
       (group3d (list (template 'temporary-child)) #:id 'root-only))))
  (define dependent
    (spatial-relation
     (template 'dependent)
     #:depends-on (list (spatial-visual-dependency '(root-only temporary-child)))
     (lambda (context source)
       (spatial-relation-context-spatial-ref context '(root-only temporary-child))
       source)))
  (check-exn
   (lambda (failure)
     (and (exn:fail? failure)
          (regexp-match? #rx"root-only spatial relation" (exn-message failure))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-sample
       (scene-add (make-scene)
                  (view3d (list root-only dependent) #:id 'world))
       0)
      'world))))
