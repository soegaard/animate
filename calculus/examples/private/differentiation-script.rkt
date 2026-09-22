#lang racket/base
;; Pure production data. Durations are draft reading/voice-over holds, not audio.
(require racket/list racket/math)
(provide (struct-out shot) script theorem-duration transition-duration
         script-duration film-duration state-at state-at-shot-end
         initial-state shot-offsets)
(struct shot (id duration panel target caption narration) #:transparent)
(define theorem-duration 22)
(define transition-duration 3/2)
(define initial-state
  (hash 'x0 1 'h 1 'point 0 'neighbour 0 'secant 0 'triangle 0
        'tangent 0 'lens 0 'zoom 1))
(define script
  (list
   (shot 'graf 10 'theorem (hash)
         "Funktionen har en graf."
         "Lad os se på, hvad sætningen siger. Funktionen f af x lig med x i anden har en graf. Det er en parabel.")
   (shot 'vaelg-punkt 12 'theorem (hash 'point 1)
         "Vi vælger et sted på x-aksen."
         "Vi vælger et vilkårligt sted på x-aksen og kalder det x nul. Det tilsvarende punkt på grafen har koordinaterne x nul og f af x nul.")
   (shot 'zoom-foerste 12 'theorem (hash 'lens 1 'zoom 40)
         "Vi zoomer ind omkring punktet."
         "At funktionen er differentiabel betyder her, uformelt, at grafen kommer til at ligne en ret linje, når vi zoomer ind omkring punktet.")
   (shot 'hold-foerste 7 'theorem (hash)
         "Grafen kommer til at ligne en ret linje."
         "Punktet bliver i midten. Vi ser stadig på den samme parabel, men nu ser den næsten ret ud.")
   (shot 'zoom-ud-foerste 6 'theorem (hash 'zoom 1)
         "Vi zoomer ud igen."
         "Lad os zoome ud igen.")
   (shot 'fjern-lup-foerste 2 'theorem (hash 'lens 0)
         ""
         "")
   (shot 'andet-punkt 7 'theorem (hash 'x0 2)
         "Vi vælger et andet punkt."
         "Vi kunne have valgt et andet sted. Lad os flytte punktet og gøre det samme igen.")
   (shot 'zoom-andet 12 'theorem (hash 'lens 1 'zoom 40)
         "Det samme sker ved et andet punkt."
         "Når vi zoomer ind omkring det nye punkt, kommer grafen igen til at ligne en ret linje. Det er betydningen af differentiabel i hele R: vi kan gøre det ved ethvert punkt.")
   (shot 'hold-andet 7 'theorem (hash)
         "Linjen kaldes tangenten."
         "Den linje, grafen ligner lokalt, kalder vi tangenten.")
   (shot 'tangent-i-lup 6 'theorem (hash 'tangent 1)
         "Tangenten lægges oven på grafen."
         "Vi lægger tangenten oven på grafen, så vi kan følge den, når vi zoomer ud.")
   (shot 'zoom-ud-andet 6 'theorem (hash 'zoom 1)
         "Vi ser tangenten i det store koordinatsystem."
         "Nu zoomer vi ud igen. Tangenten går gennem det punkt på grafen, vi valgte.")
   (shot 'fjern-lup-andet 2 'theorem (hash 'lens 0)
         ""
         "")
   (shot 'haeldning 15 'slope-meaning (hash)
         "Den afledede funktion giver tangenthældningen."
         "Den næste del af sætningen fortæller, hvad tangentens hældning er. Når den afledede funktion er to x, er tangenthældningen ved x nul lig med to gange x nul.")
   (shot 'eksempel-et 8 'slope-one (hash 'x0 1)
         "Ved 1 er tangenthældningen 2."
         "Hvis x nul er et, bliver tangenthældningen to gange et, altså to.")
   (shot 'eksempel-to 8 'slope-two (hash 'x0 2)
         "Ved 2 er tangenthældningen 4."
         "Hvis x nul er to, bliver tangenthældningen to gange to, altså fire.")
   (shot 'vilkaarligt-punkt 12 'two-goals (hash 'x0 1)
         "Vi skal bevise to ting for et vilkårligt sted."
         "For ethvert x nul skal vi vise to ting: Funktionen er differentiabel i x nul, og den afledede i x nul er to gange x nul.")
   (shot 'tretrinsreglen 12 'three-steps (hash 'tangent 0)
         "Vi bruger tretrinsreglen."
         "Vi lader nu x nul være givet. En god strategi er tretrinsreglen. Først funktions-tilvæksten, så differenskvotienten og til sidst grænseværdien.")
   (shot 'nabopunkt 15 'step-one (hash 'neighbour 1 'secant 1)
         "Vi vælger et nabopunkt og tegner sekanten."
         "Vi tager et nabopunkt på grafen. Dets x-koordinat er x nul plus h. Den rette linje gennem de to punkter er sekanten. Dens hældning kan vi regne ud.")
   (shot 'tilvaekster 18 'increments (hash 'triangle 1)
         "Vandret tilvækst og lodret tilvækst."
         "X-tilvæksten er h. Y-tilvæksten er forskellen mellem de to funktionsværdier. Den kalder vi delta y.")
   (shot 'dy-definition 20 'dy-definition (hash)
         "Trin 1: Udregn funktions-tilvæksten."
         "Funktions-tilvæksten er f af x nul plus h, minus f af x nul. Vi trækker altså den gamle y-værdi fra den nye.")
   (shot 'dy-indsaet 16 'dy-substitute (hash)
         "Vi bruger, at funktionen sætter i anden."
         "Da f af x er x i anden, får vi x nul plus h i anden, minus x nul i anden.")
   (shot 'dy-kvadrat 22 'dy-expand (hash)
         "Vi bruger første kvadratsætning."
         "Kvadratet giver x nul i anden plus h i anden plus det dobbelte produkt, to gange x nul gange h. Til sidst står der stadig minus x nul i anden.")
   (shot 'dy-forkort 14 'dy-cancel (hash)
         "De to kvadratled går ud med hinanden."
         "X nul i anden går ud med minus x nul i anden. Derfor er funktions-tilvæksten h i anden plus to gange x nul gange h.")
   (shot 'dq-definition 18 'dq-definition (hash)
         "Trin 2: Udregn differenskvotienten."
         "Differenskvotienten er sekantens hældning. Vi dividerer y-tilvæksten med x-tilvæksten, som er h. De to punkter er forskellige, så h er ikke nul.")
   (shot 'dq-del-broek 18 'dq-split (hash)
         "Vi dividerer hvert led i tælleren med h."
         "Vi deler brøken op i to. Først h i anden divideret med h, og så to gange x nul gange h divideret med h.")
   (shot 'dq-forkort 16 'dq-cancel (hash)
         "Vi har nu fundet sekantens hældning."
         "I det første led står der h gange h divideret med h, så det giver h. I det andet led går gange h og divideret med h ud med hinanden. Tilbage står h plus to gange x nul.")
   (shot 'graense-start 12 'limit-start (hash)
         "Trin 3: Undersøg grænseværdien."
         "Nu skal vi undersøge, hvad der sker med differenskvotienten, når h går mod nul. X nul er fast under denne undersøgelse.")
   (shot 'graense-approach 16 'limit-start (hash 'h 1/100 'triangle 0)
         "Nabopunktet nærmer sig det faste punkt."
         "Vi lader nabopunktet komme tættere og tættere på. Sekanthældningen er hele tiden h plus to gange x nul. H bliver mindre, mens to gange x nul er konstant.")
   (shot 'graense-regn 22 'limit-result (hash)
         "Nu bestemmer vi grænseværdien."
         "H går mod nul. To gange x nul afhænger ikke af h. Grænseværdien af summen er derfor nul plus to gange x nul, altså to gange x nul.")
   (shot 'bevis-tangent 14 'proved (hash 'neighbour 0 'secant 0 'tangent 1)
         "Sekanthældningerne har en grænseværdi."
         "Nu har vi vist, at sekanthældningerne har en grænseværdi. Derfor er funktionen differentiabel i x nul. Grænseværdien er tangentens hældning, så den afledede i x nul er to gange x nul.")
   (shot 'alle-steder 14 'proved (hash 'x0 -1)
         "Beregningen gælder for ethvert reelt sted."
         "Der var ikke noget særligt ved det x nul, vi valgte. Den samme udregning virker for ethvert reelt x nul.")
   (shot 'tilbage-til-saetning 12 'theorem (hash 'x0 1)
         "Dermed har vi bevist sætningen."
         "Funktionen f af x lig med x i anden er altså differentiabel i hele R, og dens afledede funktion er f mærke x lig med to x.")
   (shot 'opsamling 18 'summary (hash)
         "Funktions-tilvækst. Differenskvotient. Grænseværdi."
         "Det er de tre trin: Først funktions-tilvæksten, så differenskvotienten og til sidst grænseværdien. Dermed har vi bevist vores sætning.")
   ))
(define script-duration (apply + (map shot-duration script)))
(define film-duration (+ theorem-duration transition-duration script-duration))
(define shot-offsets
  (for/fold ([table (hash)] [time 0] #:result table) ([s (in-list script)])
    (values (hash-set table (shot-id s) time) (+ time (shot-duration s)))))
(define (smooth t) (* t t (- 3 (* 2 t))))
(define (apply-target state target)
  (for/fold ([state state]) ([(key value) (in-hash target)])
    (hash-set state key value)))
;; Changes occupy at most the first 2/3 of a narrated beat. The final hold
;; exposes an exact endpoint before the next operation begins.
(define (sample-change before s local)
  (define target (shot-target s))
  (for/fold ([state before]) ([(key finish) (in-hash target)])
    (define start (hash-ref before key))
    (define change-time
      (if (memq key '(point neighbour secant triangle tangent lens))
          (min 4/5 (shot-duration s))
          (min 8 (* 2/3 (shot-duration s)))))
    (define p (smooth (min 1 (max 0 (/ local change-time)))))
    (hash-set state key
      (cond [(= p 0) start] [(= p 1) finish]
            [(eq? key 'zoom) (exp (+ (log start) (* p (- (log finish) (log start)))))]
            [else (+ start (* p (- finish start)))]))))
(define (state-at time)
  (unless (and (real? time) (not (nan? time)) (not (infinite? time))
               (<= 0 time script-duration))
    (raise-argument-error 'state-at "finite time in the script interval" time))
  (let loop ([remaining script] [offset 0] [state initial-state])
    (cond [(null? remaining) state]
          [else
           (define s (car remaining))
           (define end (+ offset (shot-duration s)))
           (if (< time end)
               (sample-change state s (- time offset))
               (loop (cdr remaining) end (apply-target state (shot-target s))))])))
(define (state-at-shot-end id)
  (define s (findf (lambda (s) (eq? id (shot-id s))) script))
  (unless s (raise-argument-error 'state-at-shot-end "script shot id" id))
  (state-at (+ (hash-ref shot-offsets id) (shot-duration s))))
