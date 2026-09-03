#lang racket/base

;;;
;;; SCENE-CT: Matrices and Tables
;;;

;; Rows and cells are ordinary named groups.  The existing attention and copy
;; animations therefore select a matrix row and one vector entry by nested path
;; instead of requiring a separate matrix animation API.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (math-entry id source)
  (glyph-tex #:id id #:font-size 2/5 source))

(define (label-entry id source)
  (plain-text source #:id id #:font-size 1/5 #:font-family 'swiss
              #:color "darkslategray"))

(define (make-demo-scene)
  (define left-matrix
    (matrix
     (list (list (math-entry 'a11 "1") (math-entry 'a12 "2"))
           (list (math-entry 'a21 "3") (math-entry 'a22 "4")))
     #:id 'A #:center (vec2 -5/2 1/4)
     #:entry-width 7/10 #:entry-height 7/10
     #:column-gap 1/5 #:row-gap 1/5 #:stroke "navy"))
  (define vector-x
    (matrix
     (list (list (math-entry 'x1 "2"))
           (list (math-entry 'x2 "1")))
     #:id 'x #:center (vec2 -1/2 1/4)
     #:entry-width 7/10 #:entry-height 7/10 #:row-gap 1/5
     #:stroke "royalblue"))
  (define product
    (matrix
     (list (list (math-entry 'p1 "4"))
           (list (math-entry 'p2 "10")))
     #:id 'product #:center (vec2 5/2 1/4)
     #:entry-width 7/10 #:entry-height 7/10 #:row-gap 1/5
     #:stroke "forestgreen"))
  (define multiplication-sign
    ;; Centre each operator in the gap between the rendered matrix brackets,
    ;; rather than between the nominal centres of its neighbouring groups.
    (glyph-tex #:id 'times #:center (vec2 -51/40 1/4)
               #:font-size 2/5 "\\times"))
  (define equals-sign
    (glyph-tex #:id 'equals #:center (vec2 1 1/4)
               #:font-size 2/5 "="))
  (define calculation-table
    (table
     (list (list (label-entry 'heading-row "row")
                 (label-entry 'heading-column "column")
                 (label-entry 'heading-result "result"))
           (list (label-entry 'row-one "1")
                 (label-entry 'column-one "1")
                 (label-entry 'dot-product "4")))
     #:id 'calculation #:center (vec2 0 -9/5)
     #:cell-width 6/5 #:cell-height 1/2
     #:stroke "slategray" #:stroke-width 2))
  (define title
    (plain-text "SCENE-CT: addressable matrices and tables"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Select a row and a column by path; existing copy animations build the product."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define note
    (plain-text "(matrix-entry-path 'A 1 2)  ⇒  '(A row-1 col-2)"
                #:id 'note #:center (vec2 0 -14/5)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define initial
    (scene-add (make-scene)
               title explanation left-matrix vector-x multiplication-sign
               equals-sign calculation-table note))
  (define selected
    (scene-play
     (scene-wait initial 1)
     (animation-group
      (indicate (matrix-row-path 'A 1)
                #:color "goldenrod" #:padding 1/6 #:stroke-width 3)
      (indicate (matrix-entry-path 'x 1 1)
                #:color "royalblue" #:padding 1/6 #:stroke-width 3))
     #:duration 1))
  (define copied
    (scene-play
     (scene-wait selected 1/2)
     (transform-from-copy (matrix-row-path 'A 1) product #:path-arc -1/3)
     #:duration 2))
  (scene-wait
   (scene-play
    (scene-wait copied 1/2)
    (indicate (table-cell-path 'calculation 2 3)
              #:color "forestgreen" #:padding 1/10 #:stroke-width 3)
    #:duration 1)
   1))

(module+ main
  (run-demo "matrices-and-tables.rkt" make-demo-scene))
