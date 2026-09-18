#lang racket/base

;; Reproduce the Guide function-graph drawing path in a genuine SVG.
(require racket/class racket/cmdline racket/file racket/path
         (only-in pict draw-pict frame pict-height pict-width pict->bitmap scale)
         (only-in racket/draw svg-dc%)
         (only-in "../main.rkt"
                  axes axis-range function-graph make-scene scene-add scene->pict))

(define (save-svg picture path)
  (define target
    (new svg-dc%
         [width (pict-width picture)]
         [height (pict-height picture)]
         [output path]
         [exists 'error]))
  (send target start-doc "Animate path smoothing regression")
  (send target start-page)
  ;; This matches the manual SVG exporter. The path renderer must still select
  ;; smoothed mode inside its own delayed drawing callback.
  (send target set-smoothing 'smoothed)
  (define before (send target get-smoothing))
  (draw-pict picture target 0 0)
  (unless (eq? before (send target get-smoothing))
    (error 'probe-path-smoothing "path renderer leaked the DC smoothing mode"))
  (send target end-page)
  (send target end-doc))

(module+ main
  (define output
    (command-line #:program "tools/probe-path-smoothing.rkt"
                  #:args (destination)
                  (path->complete-path destination)))
  (when (or (file-exists? output)
            (directory-exists? output)
            (link-exists? output))
    (raise-user-error 'probe-path-smoothing
                      "use a fresh output directory: ~a"
                      output))
  (make-directory* output)

  (define coordinates
    (axes #:id 'coordinates
          #:x-range (axis-range -3 3 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 7
          #:y-length 9/2
          #:stroke "navy"))
  (define curve
    (function-graph coordinates
                    (lambda (x) (- (/ (* x x) 4) 1))
                    #:id 'curve
                    #:sample-count 81
                    #:stroke "crimson"
                    #:stroke-width 3))
  (define still
    (scene->pict (scene-add (make-scene) coordinates curve) 0))
  ;; Exact documentation wrapper used by guide-pict.
  (define guide-picture
    (frame (scale still 3/8)
           #:color "gray"
           #:line-width 1))
  (define svg-path (build-path output "guide-function-graph.svg"))
  (define png-path (build-path output "guide-function-graph.png"))
  (save-svg guide-picture svg-path)
  (define bitmap (pict->bitmap guide-picture 'smoothed))
  (unless (send bitmap save-file png-path 'png)
    (error 'probe-path-smoothing "could not save PNG"))
  (printf "Wrote ~a and ~a\n" svg-path png-path))
