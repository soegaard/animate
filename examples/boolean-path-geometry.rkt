#lang racket/base

;;;
;;; SCENE-DY: General Boolean Path Geometry
;;;

;; Two overlapping cubic paths are combined into ordinary fillable path
;; geometry. The pale blue/red outlines remain as the source operands while
;; each coloured result demonstrates one Boolean operation.

(require racket/list
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (caption id text center)
  (plain-text text #:id id #:center center
              #:font-size 1/4 #:font-family 'swiss #:font-weight 'bold
              #:color "midnightblue"))

(define unit-disk
  (path-visual-path
   (ellipse #:id 'unit-disk #:center origin #:width 9/5 #:height 9/5)))

(define (disk-pair panel-center)
  (values (path-geometry-translate unit-disk
                                   (vec2+ panel-center (vec2 -1/2 0)))
          (path-geometry-translate unit-disk
                                   (vec2+ panel-center (vec2 1/2 0)))))

(define (outline id geometry color)
  (make-path-visual geometry #:id id #:fill #f #:stroke color #:stroke-width 2))

(define (result id geometry color)
  ;; Boolean results now reconstruct exterior/hole contours. This older compact
  ;; gallery keeps its fill-only presentation; the SCENE-DY demo also strokes
  ;; concave and compound results to show that no partition seams remain.
  (make-path-visual geometry #:id id #:fill color #:stroke #f))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DY: Boolean path geometry"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Two cubic disks become union, intersection, difference, and XOR path geometry."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define panels
    (list (list 'union "union" (vec2 -3 1/2) "cornflowerblue" path-union)
          (list 'intersection "intersection" (vec2 3 1/2) "mediumpurple"
                path-intersection)
          (list 'difference "left − right" (vec2 -3 -11/5) "goldenrod"
                path-difference)
          (list 'xor "exclusive or" (vec2 3 -11/5) "seagreen" path-xor)))
  (define source-outlines
    (apply append
           (for/list ([panel (in-list panels)])
             (define panel-id (first panel))
             (define-values (left right) (disk-pair (third panel)))
             (list (outline (string->symbol (format "~a-left" panel-id))
                            left "steelblue")
                   (outline (string->symbol (format "~a-right" panel-id))
                            right "indianred")))))
  (define results
    (for/list ([panel (in-list panels)])
      (define panel-id (first panel))
      (define-values (left right) (disk-pair (third panel)))
      (result (string->symbol (format "~a-result" panel-id))
              ((fifth panel) left right #:curve-samples 12)
              (fourth panel))))
  (define captions
    (for/list ([panel (in-list panels)])
      (caption (string->symbol (format "~a-caption" (first panel)))
               (second panel)
               (vec2 (vec2-x (third panel))
                     (+ (vec2-y (third panel)) -6/5)))))
  (define initial
    (apply scene-add
           (append (list (make-scene) title explanation)
                   source-outlines captions)))
  (define revealed
    (keyword-apply
     scene-play '(#:duration) (list 2)
     (cons initial
           (append (map fade-in results)
                   (for/list ([source (in-list source-outlines)])
                     (fade-to source 1/4))))))
  (scene-wait revealed 2))

(module+ main
  (run-demo "boolean-path-geometry.rkt" make-demo-scene))
