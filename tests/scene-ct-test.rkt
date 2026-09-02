#lang racket/base

;;;
;;; SCENE-CT Matrix and Table Tests
;;;

(require rackunit
         (only-in pict pict?)
         "../main.rkt")

(define (entry text)
  ;; Repeated local ids are intentional: matrix/table path segments identify
  ;; which row and column contains this visual.
  (plain-text text #:id 'entry #:font-size 1/3 #:color "navy"))

(define sample-matrix
  (matrix
   (list (list (entry "1") (entry "2"))
         (list (entry "3") (entry "4")))
   #:id 'A
   #:center (vec2 -2 0)
   #:entry-width 3/4
   #:entry-height 3/4
   #:column-gap 1/4
   #:row-gap 1/4))

(define sample-table
  (table
   (list (list (entry "term") (entry "value"))
         (list (entry "x") (entry "7")))
   #:id 'values
   #:center (vec2 2 0)
   #:cell-width 1
   #:cell-height 3/4
   #:stroke "darkslategray"))

(module+ test
  ;; Stable names are intentionally local to their parent rows.  They produce
  ;; concise readable nested paths while distinct paths still select distinct
  ;; cells.
  (check-equal? (matrix-row-id 2) 'row-2)
  (check-equal? (matrix-column-id 1) 'col-1)
  (check-equal? (matrix-row-path 'A 2) '(A row-2))
  (check-equal? (matrix-entry-path 'A 2 1) '(A row-2 col-1))
  (check-equal? (matrix-bracket-path 'A 'left) '(A left-bracket))
  (check-equal? (table-cell-path 'values 1 2) '(values row-1 col-2))

  (define initial
    (scene-add (make-scene) sample-matrix sample-table))
  (check-true
   (scene-state-has? (scene-current-state initial)
                     (matrix-entry-path 'A 1 1)))
  (check-true
   (scene-state-has? (scene-current-state initial)
                     (matrix-entry-path 'A 2 1)))
  (check-equal?
   (visual-id (scene-state-ref (scene-current-state initial)
                               (matrix-entry-path 'A 1 1)))
   'col-1)
  (check-equal?
   (visual-id (scene-state-ref (scene-current-state initial)
                               '(A row-2 col-1 entry)))
   'entry)
  (check-true
   (scene-state-has? (scene-current-state initial)
                     (matrix-bracket-path 'A 'right)))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state initial)
                     (matrix-bracket-path 'A 'left)))
   (vec2 -7/8 0))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state initial)
                     (matrix-bracket-path 'A 'right)))
   (vec2 7/8 0))
  (check-true
   (scene-state-has? (scene-current-state initial)
                     '(values grid-column-0)))
  (check-true
   (scene-state-has? (scene-current-state initial)
                     (table-cell-path 'values 2 2)))

  ;; Existing nested animation APIs now operate on a cell without changing a
  ;; same-named sibling in another row.
  (define moved
    (scene-play
     initial
     (move-to (matrix-entry-path 'A 1 1) (vec2 -3/2 1))
     #:duration 1))
  (check-equal?
   (visual-position
    (scene-visual-at moved (matrix-entry-path 'A 1 1) 1))
   (vec2 -3/2 1))
  (check-not-equal?
   (visual-position
    (scene-visual-at moved (matrix-entry-path 'A 2 1) 1))
   (vec2 -3/2 1))

  ;; Matrix brackets, table grid lines, and ordinary text entries render
  ;; through the standard group composition path.
  (check-true (pict? (scene->pict initial 0)))

  ;; Construction rejects malformed grids and invalid dimensions early.
  (check-exn exn:fail:contract?
             (lambda () (matrix '() #:id 'empty)))
  (check-exn exn:fail:contract?
             (lambda ()
               (matrix (list (list (entry "1"))
                             (list (entry "2") (entry "3")))
                       #:id 'ragged)))
  (check-exn exn:fail:contract?
             (lambda ()
               (table (list (list (entry "1")))
                      #:id 'flat #:cell-width 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (matrix (list (list (entry "1")))
                       #:id 'stretched #:scale (vec2 1 2))))
  (check-exn exn:fail:contract?
             (lambda () (matrix-row-id 0)))
  (check-exn exn:fail:contract?
             (lambda () (matrix-bracket-path 'A 'top))))
