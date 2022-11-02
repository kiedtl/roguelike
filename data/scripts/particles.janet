# TODO: remove if this is accepted into the stdlib and when the next version of
# Janet is released.
(defn deepclone [x]
  (case (type x)
    :array (array/slice (map deepclone x))
    :tuple (tuple/slice (map deepclone x))
    :table (if-let [p (table/getproto x)]
             (deepclone (merge (table/clone p) x))
             (table ;(map deepclone (kvs x))))
    :struct (struct ;(map deepclone (kvs x)))
    :buffer (buffer x)
    x))

(defn random-choose [array]
  (array (math/floor (* (math/random) (length array)))))

(def Coord @{
             :x 0 :y 0                                   # Can be fractional.
             :eq? (fn [a b]
                    (and (= (math/round (a :x)) (math/round (b :x)))
                         (= (math/round (a :y)) (math/round (b :y)))))
             :distance (fn [a b]
                         (let [diffx (math/abs (- (a :x) (b :x)))
                               diffy (math/abs (- (a :y) (b :y)))]
                           (max diffx diffy)))
             })
(defn new-coord [&opt x y]
  (default x 0)
  (default y 0)
  (table/setproto @{ :x x :y y } Coord))

(def Rect @{
             :start (new-coord)
             :height 0
             :width 0
             :contains? (fn [self coord]
                          (and
                            (>= (coord :x) ((self :start) :x))
                            (>= (coord :y) ((self :start) :y))
                            (< (coord :x) (+ ((self :start) :x) (self :width)))
                            (< (coord :y) (+ ((self :start) :y) (self :height)))))
             })
(defn new-rect [&opt start width height]
  (default start (new-coord))
  (default width 0)
  (default height 0)
  (table/setproto @{ :start start :width width :height height } Rect))

(def Tile @{ :ch " " :fg 0xffffff :bg 0 :bg-mix 0.8 })
(defn new-tile [table] (table/setproto table Tile))

# Used by Particle, so must be defined before it
(defn get-parent [self recurse]
  (if (= recurse 0)
    self
    (get-parent (self :parent) (- recurse 1))))

(def Particle @{
                :tile (new-tile @{})
                :speed 0
                :coord (new-coord)
                :target (table/setproto @{} Coord)
                :triggers @[]
                :lifetime 99999

                :parent nil
                :dead false
                :original-tile nil
                :age 0

                :tick (fn [self ticks ctx]
                        # Update particle position
                        (let [diffx (- ((self :target) :x) ((self :coord) :x))
                              diffy (- ((self :target) :y) ((self :coord) :y))
                              angle (math/atan2 diffy diffx)
                              # Don't move past target
                              speed (min (math/sqrt (+ (* diffx diffx) (* diffy diffy))) (self :speed))]
                          (+= ((self :coord) :x) (* speed (math/cos angle)))
                          (+= ((self :coord) :y) (* speed (math/sin angle))))

                       (each trigger (self :triggers)
                         (if (((trigger 0) 0) self ticks ctx ;(slice (trigger 0) 1))
                           (((trigger 1) 0) self ticks ctx ;(slice (trigger 1) 1))))
                        (++ (self :age))

                        (or (not (:contains? (ctx :bounds) (self :coord)))
                            (:eq? (self :coord) (self :target))
                            (>= (self :age) (self :lifetime))))

                :COND-true (fn [&] true)
                :COND-parent-dead? (fn [self ticks ctx recurse &]
                                     (let [parent (get-parent self recurse)]
                                       (parent :dead)))

                :TRIG-scramble-glyph (fn [self ticks ctx chars &]
                                       (def new-char (random-choose chars))
                                       (put (self :tile) :ch (string/from-bytes new-char)))
                :TRIG-modify-color (fn [self ticks ctx which how &]
                                     (def factor
                                       (case (how 0)
                                         :completed-journey
                                           (/ (:distance (self :coord) (self :target))
                                              (:distance (((self :parent) :particle) :coord) (self :target)))
                                         :completed-parent-lifetime # (:completed-parent-lifetime parent-recurse factor)
                                           (let [parent (get-parent self (how 1))]
                                             #(eprint "parent-age: " (parent :age) "; parent-lifetime: " (parent :lifetime))
                                             (min 1 (- 1 (/ (parent :age) (* (how 2) (parent :lifetime))))))))
                                     (def r (math/floor (* (band (brshift ((self :original-tile) which) 16) 0xFF) factor)))
                                     (def g (math/floor (* (band (brshift ((self :original-tile) which)  8) 0xFF) factor)))
                                     (def b (math/floor (* (band (brshift ((self :original-tile) which)  0) 0xFF) factor)))
                                     (put (self :tile) which (bor (blshift r 16) (blshift g 8) b)))
                :TRIG-create-emitter (fn [self ticks ctx emitter-template]
                                       (def new-emitter (deepclone emitter-template))
                                       (put (new-emitter :particle) :coord (self :coord))
                                       (put (new-emitter :particle) :target (((self :parent) :particle) :target))
                                       (put new-emitter :parent self)
                                       (array/push (ctx :emitters) new-emitter))
                :TRIG-die (fn [self &]
                            (put self :dead true))
                })
(defn new-particle [table] (table/setproto table Particle))

(def Emitter @{
               :particle (table/setproto @{} Particle)
               :lifetime nil                            # how many ticks before shutting down
               :spawn-count 1                           # number of particles to spawn each tick
               :spawn-delay 0                           # ticks to wait between spawns
               :triggers []
               :vary-particle-speed 0
               :get-spawn-coord (fn [self ticks ctx target] target)

               # Unimplemented
               :birth-delay nil                         # how many ticks to wait before activating

               # Context
               :delay-until-spawn 0
               :age 0
               :dead false
               :inactive false
               :parent nil
               :total-spawned 0

               :tick (fn [self ticks ctx]
                       (if (and (not (self :inactive))
                                (<= (self :delay-until-spawn) 0))
                         (do
                           (def spawn-count
                             (case (type (self :spawn-count))
                               :function (:spawn-count self ticks ctx)
                               :number (self :spawn-count)))
                           (for i 0 spawn-count
                             (do
                               (var new-particle (deepclone (self :particle)))
                               (put new-particle :coord (:get-spawn-coord self ticks ctx))
                               (put new-particle :parent self)
                               (put new-particle :original-tile (new-particle :tile))
                               (put new-particle :speed (+ (new-particle :speed)
                                                           (* (self :vary-particle-speed) (random-choose [-1 0 1]) (math/random))))
                               (array/push (ctx :particles) new-particle)
                               (++ (self :total-spawned))))
                           (put self :delay-until-spawn (self :spawn-delay))))
                       (each trigger (self :triggers)
                         (if (((trigger 0) 0) self ticks ctx ;(slice (trigger 0) 1))
                           (((trigger 1) 0) self ticks ctx ;(slice (trigger 1) 1))))
                       (++ (self :age))
                       (-- (self :delay-until-spawn))
                       (> (self :age) (self :lifetime)))

               :COND-age-eq? (fn [self ticks ctx num]
                               (= (self :age) num))

               :TRIG-inactivate (fn [self ticks ctx]
                                  (put self :inactive true))
               })
(defn new-emitter [table] (table/setproto table Emitter))

(def Context @{
               :target (new-coord)
               :bounds (new-rect)
               :particles @[]
               :emitters @[]
               })
(defn new-context [target area-size emitters]
  (table/setproto @{ :bounds area-size :target target :emitters emitters } Context))

(def emitters-table @{
  "test" @[
    (new-emitter @{
      #:particle (new-particle @{
      #  :tile (new-tile @{ :bg-mix 0 })
      #  #:tile (new-tile @{ :ch "X" :fg 0 :bg 0xff2211 })
      #  :speed 1
      #  :triggers @[
      #    [[:COND-true] [:TRIG-create-emitter (new-emitter @{
      #      :lifetime 1
      #    })]]
      #  ]
      #})
      :particle (new-particle @{
        :tile (new-tile @{ :ch "Z" :fg 0x9fefff :bg 0x8fdfff :bg-mix 0.65 })
        :speed 0
        :triggers @[
          [[:COND-true] [:TRIG-scramble-glyph "AEFHIKLMNTYZ13457*-=+~?!@#%&"]]
          [[:COND-true] [:TRIG-modify-color :bg @(:completed-parent-lifetime 1 3.5)]]
          [[:COND-parent-dead? 1] [:TRIG-die]]
        ]
      })
      :lifetime 8
      :triggers [ [[:COND-age-eq? 0] [:TRIG-inactivate]] ] # disable after first volley
      :spawn-count (fn [self &] (+ (:distance ((self :particle) :coord) ((self :particle) :target)) 1))
      :get-spawn-coord (fn [self ticks ctx]
                         (let [target ((self :particle) :target)
                               coord ((self :particle) :coord)
                               diffx (- (target :x) (coord :x))
                               diffy (- (target :y) (coord :y))
                               angle (math/atan2 diffy diffx)
                               n (+ (% (self :total-spawned) (:distance coord target)) 1)]
                           (new-coord (+ (coord :x) (* n (math/cos angle)))
                                      (+ (coord :y) (* n (math/sin angle))))))
     })
  ]
})

(defn animation-init [initialx initialy targetx targety boundsx boundsy bounds-width bounds-height emitters-set]
  (def initial (new-coord initialx initialy))
  (def target (new-coord targetx targety))
  (def area-size (new-rect (new-coord boundsx boundsy) bounds-width bounds-height))
  (def emitters (deepclone (emitters-table emitters-set)))

  # set targets for emitter particles
  (each emitter emitters
    (put (emitter :particle) :coord initial)
    (put (emitter :particle) :target target))

  (new-context target area-size emitters))

(defn animation-tick [ctx ticks]

  (loop [i :range [0 (length (ctx :emitters))]]
    (def emitter ((ctx :emitters) i))
    (if (not (emitter :dead))
      (if (:tick emitter ticks ctx)
        (put emitter :dead true))))

  (var particles @[])
  (loop [i :range [0 (length (ctx :particles))]]
    (def particle ((ctx :particles) i))
    (if (not (particle :dead))
      (do
        (if (:tick particle ticks ctx)
          (put particle :dead true))
        (array/push particles @[((particle :tile) :ch)
                                ((particle :tile) :fg)
                                ((particle :tile) :bg)
                                ((particle :tile) :bg-mix)
                                (math/round ((particle :coord) :x))
                                (math/round ((particle :coord) :y))]))))

  particles)

# (defn move [initial target speed]
#   (var new initial)
#                         (var angle (math/atan2 (- (target :y) (initial :y))
#                                                (- (target :x) (initial :x))))
#                         (put new :x (* speed (math/cos angle)))
#                         (put new :y (* speed (math/sin angle)))
#                         new
#                         )
# (def res (move (new-coord 0 0) (new-coord 4 1) 0.2))
# (eprint (res :x) ", " (res :y))
