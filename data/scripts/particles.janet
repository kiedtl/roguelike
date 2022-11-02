(def Coord @{
             :x 0 :y 0                                   # Can be fractional.
             :eq? (fn [a b]
                    (and (= (math/round (a :x)) (math/round (b :x)))
                         (= (math/round (a :y)) (math/round (b :y)))))
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

(def Tile @{ :ch " " :fg 0 :bg 0 })

(def Particle @{
                :tile (table/setproto @{} Tile)
                :speed 0
                :coord (new-coord)
                :target (table/setproto @{} Coord)
                :dead false

                :tick (fn [self ticks ctx]
                        (var angle (math/atan2 (- ((self :target) :y) ((self :coord) :y))
                                               (- ((self :target) :x) ((self :coord) :x))))
                        (+= ((self :coord) :x) (* (self :speed) (math/cos angle)))
                        (+= ((self :coord) :y) (* (self :speed) (math/sin angle)))

                        (or (not (:contains? (ctx :bounds) (self :coord)))
                            (:eq? (self :coord) (self :target))))
                })

(def Emitter @{
               :particle (table/setproto @{} Particle)
               :lifetime nil                            # how many ticks before shutting down
               :spawn-count 1                           # number of particles to spawn each tick

               # Unimplemented
               :birth-delay nil                         # how many ticks to wait before activating
               :spawn-delay 1                           # ticks to wait between spawns (default: 1)

               # Context
               :age 0
               :dead false

               :tick (fn [self ticks ctx]
                       (for i 0 (self :spawn-count)
                         (do
                           (array/push (ctx :particles) (self :particle))))
                       (++ (self :age))
                       (> (self :age) (self :lifetime)))

               })

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
                        (table/setproto @{
                                          :particle (table/setproto @{
                                                                      :tile (table/setproto @{ :ch "o" } Tile)
                                                                      :speed 0.2
                                                                      } Particle)
                                          :lifetime 3
                                          } Emitter)
                        ]
                })

(defn animation-init [initialx initialy targetx targety boundsx boundsy bounds-width bounds-height emitters-set]
  (def initial (new-coord initialx initialy))
  (def target (new-coord targetx targety))
  (def area-size (new-rect (new-coord boundsx boundsy) bounds-width bounds-height))
  (def emitters (array/concat @[] (emitters-table emitters-set)))

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
        (array/push particles @[((particle :tile) :ch)
                                (math/round ((particle :coord) :x))
                                (math/round ((particle :coord) :y))])
        (if (:tick particle ticks ctx)
          (put particle :dead true)))))

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
