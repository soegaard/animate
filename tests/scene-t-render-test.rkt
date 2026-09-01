#lang racket/base

;;;
;;; SCENE-T Rendering Tests
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width pict?)
         "../main.rkt")

(module+ test
  (define test-camera
    (make-camera #:width 640
                 #:height 360
                 #:world-width 16))
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -3 3 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 6
          #:y-length 4))
  (define grid
    (axes-grid-lines coordinate-axes
                     #:id 'grid))
  (define labels
    (axes-number-labels coordinate-axes
                        #:id-prefix 'axis-label))
  (define scale-line
    (number-line (axis-range -2 4 1)
                 #:id 'scale-line
                 #:center (vec2 0 -3)
                 #:length 6
                 #:end-tip? #t))
  (define line-labels
    (number-line-number-labels scale-line
                               #:id-prefix 'line-label))

  (define line-pict
    (visual->pict scale-line test-camera))
  (check-true (pict? line-pict))
  (check-true (> (pict-width line-pict) 0))
  (check-true (> (pict-height line-pict) 0))

  (define grid-pict
    (visual->pict grid test-camera))
  (check-true (> (pict-width grid-pict) 0))
  (check-true (> (pict-height grid-pict) 0))

  (define diagram
    (group
     (append (list grid coordinate-axes scale-line)
             labels
             line-labels)
     #:id 'diagram))
  (define scene
    (scene-wait
     (scene-play (make-scene)
                 (fade-in diagram)
                 #:duration 1)
     1/2))
  (define first-pict
    (scene->pict scene 0 #:camera test-camera))
  (define last-pict
    (scene->pict scene 3/2 #:camera test-camera))
  (check-equal? (pict-width first-pict) 640)
  (check-equal? (pict-height first-pict) 360)
  (check-equal? (pict-width last-pict) 640)
  (check-equal? (pict-height last-pict) 360)

  (define output-directory
    (make-temporary-file "scene-t-frames~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-render
        (render-frames! scene
                        output-directory
                        #:fps 10
                        #:camera test-camera))
      (check-equal? (length first-render) 15)
      (define first-bytes
        (file->bytes (car first-render)))
      (define second-render
        (render-frames! scene
                        output-directory
                        #:fps 10
                        #:camera test-camera))
      (check-equal? (length second-render) 15)
      (check-equal? first-bytes
                    (file->bytes (car second-render))))
    (lambda ()
      (delete-directory/files output-directory))))
